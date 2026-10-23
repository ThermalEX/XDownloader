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
  }) : _client = client ?? http.Client() {
    settings.addListener(_privacyChanged);
  }
  final Directory root;
  final SettingsRepository settings;
  final http.Client _client;
  final _queue = SerialQueue();
  final _files = <String, CoverCacheEntry>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _requests = <Completer<void>>{};
  static const maxImageBytes = 4 * 1024 * 1024;
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
    if (settings.value.privacyMode) _invalidate();
  }

  void _invalidate() {
    _generation++;
    _pending.clear();
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    _requests.clear();
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
        final entry = _files[name];
        if (entry == null) return null;
        try {
          final size = (await entry.file.stat()).size;
          if (size <= 0 || size > maxImageBytes) {
            await entry.file.delete();
            _files.remove(name);
            return null;
          }
          final bytes = await entry.file.readAsBytes();
          final accessed = DateTime.now();
          await entry.file.setLastModified(accessed);
          _files[name] = CoverCacheEntry(entry.file, bytes.length, accessed);
          return bytes;
        } on FileSystemException {
          _files.remove(name);
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
      _files.remove(entry.file.uri.pathSegments.last);
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
