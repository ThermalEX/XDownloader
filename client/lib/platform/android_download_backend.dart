import 'dart:async';

import 'package:flutter/services.dart';

import '../core/models/app_failure.dart';
import '../core/models/download.dart';
import 'download_backend.dart';
import 'platform_bridge.dart';

class AndroidDownloadBackend implements DownloadBackend {
  AndroidDownloadBackend({PlatformCall? call}) : call = call ?? callPlatform {
    _updates = StreamController<BackendTaskSnapshot>.broadcast(
      onListen: () => _timer = Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _poll(),
      ),
      onCancel: () => _timer?.cancel(),
    );
  }
  static const channel = platformChannel;
  final PlatformCall call;
  late final StreamController<BackendTaskSnapshot> _updates;
  final _publications = <String, Future<SavedFile>>{};
  final _thumbnails = <String, Future<Uint8List?>>{};
  Timer? _timer;
  bool _polling = false;
  Future<Object?> _call(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await call(method, args);
    } on PlatformException catch (e) {
      final kind =
          FailureKind.values.where((v) => v.name == e.code).firstOrNull ??
          FailureKind.storage;
      throw AppFailure(
        kind,
        kind == FailureKind.fileMissing ? '文件不存在或已被移走' : '无法完成文件操作',
        e.message,
      );
    }
  }

  Future<void> _poll() async {
    if (_polling || _updates.isClosed) return;
    _polling = true;
    try {
      for (final item in await snapshot()) {
        if (!_updates.isClosed) _updates.add(item);
      }
    } catch (e, stack) {
      if (!_updates.isClosed) _updates.addError(e, stack);
    } finally {
      _polling = false;
    }
  }

  @override
  Stream<BackendTaskSnapshot> get updates => _updates.stream;
  @override
  Future<void> initialize() async {
    await _call('initialize');
  }

  @override
  Future<void> enqueue(DownloadRequest request) async {
    await _call('enqueue', request.toJson());
  }

  @override
  Future<void> cancel(String taskId) async {
    await _call('cancel', {'taskId': taskId});
  }

  @override
  Future<List<BackendTaskSnapshot>> snapshot() async {
    final data = await _call('snapshot') as List;
    return data.map((value) {
      final m = Map<String, dynamic>.from(value as Map);
      return BackendTaskSnapshot(
        taskId: m['taskId'] as String,
        phase: m['phase'] == 'failed' && m['canPublish'] == true
            ? BackendPhase.transferred
            : BackendPhase.values.byName(m['phase'] as String),
        bytes: (m['bytes'] as num).toInt(),
        totalBytes: (m['totalBytes'] as num?)?.toInt(),
        stagingPath: m['stagingPath'] as String?,
        request: m['request'] == null
            ? null
            : DownloadRequest.fromJson(
                Map<String, dynamic>.from(m['request'] as Map),
              ),
        savedFile: m['savedFile'] == null
            ? null
            : SavedFile.fromJson(
                Map<String, dynamic>.from(m['savedFile'] as Map),
              ),
        error: m['error'] == null
            ? null
            : AppFailure(FailureKind.storage, '下载未完成', m['error'] as String),
      );
    }).toList();
  }

  @override
  Future<SavedFile> publish(String taskId) => _publications.putIfAbsent(
    taskId,
    () async {
      try {
        final data = await _call('publish', {'taskId': taskId});
        final file = SavedFile.fromJson(Map<String, dynamic>.from(data as Map));
        if (file.locator.isEmpty ||
            file.bytes <= 0 ||
            !file.mimeType.startsWith('video/')) {
          throw const AppFailure(FailureKind.storage, '保存的文件无效');
        }
        return file;
      } catch (_) {
        _publications.remove(taskId);
        rethrow;
      }
    },
  );
  @override
  Future<void> discardStaging(String taskId) async {
    await _call('discardStaging', {'taskId': taskId});
  }

  @override
  Future<void> open(SavedFile file) async {
    await _call('open', file.toJson());
  }

  @override
  Future<void> deleteSavedFile(SavedFile file) async {
    await _call('deleteSavedFile', file.toJson());
    _thumbnails.remove(file.locator);
  }

  @override
  Future<void> ensureReadable(SavedFile file) async {
    await _call('ensureReadable', file.toJson());
  }

  @override
  Future<Uint8List?> thumbnailSavedFile(SavedFile file) {
    if (!_thumbnails.containsKey(file.locator) && _thumbnails.length >= 32) {
      _thumbnails.remove(_thumbnails.keys.first);
    }
    return _thumbnails.putIfAbsent(file.locator, () async {
      try {
        return await _call('thumbnail', file.toJson()) as Uint8List?;
      } catch (_) {
        _thumbnails.remove(file.locator);
        return null;
      }
    });
  }

  @override
  Future<void> openDirectory() async {
    await _call('openDirectory');
  }

  Future<void> close() async {
    _thumbnails.clear();
    _timer?.cancel();
    await _updates.close();
  }
}
