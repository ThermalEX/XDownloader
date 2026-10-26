import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage/serial_queue.dart';
import 'settings_repository.dart';

class CoverCacheEntry {
  const CoverCacheEntry(this.file, this.bytes, this.accessed);
  final File file;
  final int bytes;
  final DateTime accessed;
}

/// Disposable covers only. Never owns public video files or snapshot data.
class CoverCacheRepository extends ChangeNotifier {
  CoverCacheRepository({
    required this.root,
    required this.settings,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _previousLimitMb = settings.value.coverCacheLimitMb {
    settings.addListener(_privacyChanged);
  }
  final Directory root;
  final SettingsRepository settings;
  final http.Client _client;
  final _queue = SerialQueue();
  final _files = <String, CoverCacheEntry>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _requests = <Completer<void>>{};
  // Insertion order is the byte-cache LRU, oldest first.
  final _memory = <String, Uint8List>{};
  final _dirtyAccesses = <String, CoverCacheEntry>{};
  int _memoryBytes = 0;
  int _previousLimitMb;
  Timer? _accessTimer;
  static const maxImageBytes = 4 * 1024 * 1024;
  static const _maxMemoryBytes = 8 * 1024 * 1024;
  static const _maxMemoryEntries = 32;
  static const _accessWriteInterval = Duration(seconds: 30);
  static final _ownName = RegExp(r'^[a-f0-9]{64}\.jpg$');
  int _generation = 0;
  bool _closed = false;
  int get limitMb => settings.value.coverCacheLimitMb;
  int get usedBytes =>
      _files.values.fold(0, (total, entry) => total + entry.bytes);
  List<CoverCacheEntry> get entries => List.unmodifiable(
    _files.values.toList()..sort((a, b) => b.accessed.compareTo(a.accessed)),
  );
  bool _valid(int generation) =>
      !_closed && generation == _generation && !settings.value.privacyMode;
  String _name(String key) => '${sha256.convert(utf8.encode(key))}.jpg';
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _privacyChanged() {
    final limit = limitMb;
    if (settings.value.privacyMode || limit < _previousLimitMb) _invalidate();
    _previousLimitMb = limit;
  }

  void _invalidate() {
    _generation++;
    _pending.clear();
    _memory.clear();
    _memoryBytes = 0;
    _dirtyAccesses.clear();
    _accessTimer?.cancel();
    _accessTimer = null;
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    _requests.clear();
  }

  void _forgetMemory(String name) {
    final removed = _memory.remove(name);
    if (removed != null) _memoryBytes -= removed.length;
  }

  void _remember(String name, Uint8List bytes) {
    _forgetMemory(name);
    final budget = (limitMb * 1024 * 1024).clamp(0, _maxMemoryBytes);
    if (bytes.length > budget || budget == 0) return;
    while (_memory.isNotEmpty &&
        (_memoryBytes + bytes.length > budget ||
            _memory.length >= _maxMemoryEntries)) {
      _forgetMemory(_memory.keys.first);
    }
    _memory[name] = bytes;
    _memoryBytes += bytes.length;
  }

  void _touch(String name) {
    final entry = _files[name];
    if (entry == null) return;
    final touched = CoverCacheEntry(entry.file, entry.bytes, DateTime.now());
    // Eviction always sees exact access order even between disk write batches.
    _files[name] = touched;
    _dirtyAccesses[name] = touched;
    if (_accessTimer != null) return;
    final generation = _generation;
    _accessTimer = Timer(_accessWriteInterval, () {
      _accessTimer = null;
      unawaited(_queue.run(() => _flushAccesses(generation)));
    });
  }

  Future<void> _flushAccesses(int generation) async {
    final pending = Map<String, CoverCacheEntry>.of(_dirtyAccesses);
    for (final item in pending.entries) {
      if (!_valid(generation)) return;
      if (!identical(_files[item.key], item.value)) continue;
      try {
        await item.value.file.setLastModified(item.value.accessed);
      } on FileSystemException {
        // Recency persistence is best effort, just like the image disk cache.
      }
      if (identical(_dirtyAccesses[item.key], item.value)) {
        _dirtyAccesses.remove(item.key);
      }
    }
  }

  Future<void> initialize() => _queue.run(() async {
    await root.create(recursive: true);
    await for (final entity in root.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          name.endsWith('.part') &&
          _ownName.hasMatch(name.substring(0, name.length - 5))) {
        await entity.delete();
        continue;
      }
      if (entity is! File || !_ownName.hasMatch(name)) continue;
      final stat = await entity.stat();
      if (stat.size <= 0 || stat.size > maxImageBytes) {
        await entity.delete();
        continue;
      }
      _files[name] = CoverCacheEntry(entity, stat.size, stat.modified);
    }
    await _trim();
    _notify();
  });

  Future<Uint8List?> get(String key, Future<Uint8List?> Function() load) {
    if (_closed || settings.value.privacyMode) return Future.value();
    final previous = _pending[key];
    if (previous != null) return previous;
    final generation = _generation;
    late final Future<Uint8List?> work;
    work = _load(_name(key), generation, load).whenComplete(() {
      if (identical(_pending[key], work)) _pending.remove(key);
    });
    _pending[key] = work;
    return work;
  }

  Future<Uint8List?> _load(
    String name,
    int generation,
    Future<Uint8List?> Function() load,
  ) async {
    try {
      final cached = await _queue.run(() async {
        if (!_valid(generation)) return null;
        final warm = _memory[name];
        if (warm != null) {
          _remember(name, warm);
          _touch(name);
          return warm;
        }
        final entry = _files[name];
        if (entry == null) return null;
        try {
          final size = (await entry.file.stat()).size;
          if (size <= 0 || size > maxImageBytes) {
            await entry.file.delete();
            _files.remove(name);
            _dirtyAccesses.remove(name);
            return null;
          }
          final bytes = await entry.file.readAsBytes();
          if (!_valid(generation)) return null;
          _files[name] = CoverCacheEntry(
            entry.file,
            bytes.length,
            entry.accessed,
          );
          _remember(name, bytes);
          _touch(name);
          return bytes;
        } on FileSystemException {
          _files.remove(name);
          _dirtyAccesses.remove(name);
          _forgetMemory(name);
          return null;
        }
      });
      if (!_valid(generation)) return null;
      if (cached != null) return cached;
      final data = await load();
      if (!_valid(generation) ||
          data == null ||
          data.isEmpty ||
          data.length > maxImageBytes) {
        return null;
      }
      try {
        await _queue.run(() async {
          if (!_valid(generation) || data.length > limitMb * 1024 * 1024) {
            return;
          }
          final file = File('${root.path}/$name');
          final temp = File('${file.path}.part');
          try {
            await temp.writeAsBytes(data, flush: true);
            if (!_valid(generation)) return;
            await temp.rename(file.path);
            if (!_valid(generation)) {
              await file.delete();
              return;
            }
            _files[name] = CoverCacheEntry(file, data.length, DateTime.now());
            await _trim();
            if (_valid(generation) && _files.containsKey(name)) {
              _remember(name, data);
            }
            _notify();
          } finally {
            if (await temp.exists()) await temp.delete();
          }
        });
      } on FileSystemException {
        /* A disk cache failure must not hide a loaded cover. */
      }
      return _valid(generation) ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _trim() async {
    var used = usedBytes;
    if (used <= limitMb * 1024 * 1024) return;
    for (final entry in entries.reversed) {
      if (used <= limitMb * 1024 * 1024) break;
      if (await entry.file.exists()) await entry.file.delete();
      final name = entry.file.uri.pathSegments.last;
      _files.remove(name);
      _dirtyAccesses.remove(name);
      _forgetMemory(name);
      used -= entry.bytes;
    }
  }

  Future<void> setLimitMb(int value) async {
    if (value < 0 || value > 2048) throw ArgumentError.value(value);
    await settings.edit((s) => s.copyWith(coverCacheLimitMb: value));
    await _queue.run(() async {
      await _trim();
      _notify();
    });
  }

  Future<void> clear() {
    _invalidate();
    return _queue.run(() async {
      for (final entry in _files.values) {
        if (await entry.file.exists()) await entry.file.delete();
      }
      _files.clear();
      _notify();
    });
  }

  Future<Uint8List?> remote(String key, Uri url) => get(key, () async {
    final abort = Completer<void>();
    final generation = _generation;
    _requests.add(abort);
    try {
      var target = url;
      for (var hop = 0; hop < 4; hop++) {
        if (!_valid(generation)) return null;
        if (target.scheme != 'https' ||
            target.userInfo.isNotEmpty ||
            target.host.isEmpty) {
          return null;
        }
        final request = http.AbortableRequest(
          'GET',
          target,
          abortTrigger: abort.future,
        )..followRedirects = false;
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 8));
        if (!_valid(generation)) {
          await response.stream.listen((_) {}).cancel();
          return null;
        }
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}).cancel();
          if (location == null) return null;
          target = target.resolve(location);
          continue;
        }
        if (response.statusCode != 200 ||
            !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
              'image/',
            ) ||
            (response.contentLength ?? 0) > maxImageBytes) {
          await response.stream.listen((_) {}).cancel();
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 8),
        )) {
          if (bytes.length + chunk.length > maxImageBytes) return null;
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      }
      return null;
    } finally {
      _requests.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  });

  @override
  void dispose() {
    _closed = true;
    _invalidate();
    settings.removeListener(_privacyChanged);
    _client.close();
    super.dispose();
  }
}
