import 'package:flutter/foundation.dart';

import 'dart:async';

import '../../core/models/app_failure.dart';
import '../../core/models/download.dart';
import '../../core/models/download_history.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/post_link.dart';
import '../../platform/download_backend.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';
import 'cover_cache_repository.dart';

class DownloadRepository extends ChangeNotifier {
  DownloadRepository({
    required this.store,
    required this.backend,
    this.coverCache,
    this.refreshRequest,
  });
  final CoverCacheRepository? coverCache;
  final SnapshotStore store;
  final DownloadBackend backend;
  final Future<DownloadRequest> Function(DownloadRequest, ParseCancellation)?
  refreshRequest;
  final _queue = SerialQueue();
  List<DownloadRecord> _records = const [];
  List<DownloadHistoryEntry> _history = const [];
  Set<String> _historySuppressed = {};
  final _ignored = <String>{};
  final _diagnostics = <String>[];
  final _retries = <String, _PendingRetry>{};
  StreamSubscription<BackendTaskSnapshot>? _subscription;
  bool _disposed = false;
  AppFailure? storageFailure;
  List<DownloadRecord> get records => _records;
  List<DownloadHistoryEntry> get history => _history;
  ({Uri url, String title})? sourceForFavorite(String taskId) {
    final record = _records.where((r) => r.taskId == taskId).firstOrNull;
    if (record == null || record.phase != DownloadPhase.completed) return null;
    final history = _history.where((h) => h.taskId == taskId).firstOrNull;
    for (final url in [record.request.postUrl, history?.postUrl]) {
      final post = url == null ? null : PostLink.tryParse(url.toString());
      if (post != null) {
        return (
          url: post.canonicalUrl,
          title: record.request.displayName.replaceFirst(
            RegExp(r'\.mp4$', caseSensitive: false),
            '',
          ),
        );
      }
    }
    return null;
  }

  List<String> get diagnostics => List.unmodifiable(_diagnostics);
  void _note(Object error) {
    final value = '$error';
    if (_diagnostics.contains(value)) return;
    if (_diagnostics.length >= 50) _diagnostics.removeAt(0);
    _diagnostics.add(value);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final m = await store.read('downloads');
    try {
      _records = List.unmodifiable(
        (m['records'] as List? ?? []).map(
          (v) => DownloadRecord.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
      _ignored.addAll((m['ignored'] as List? ?? []).cast<String>());
      _historySuppressed = (m['historySuppressed'] as List? ?? [])
          .cast<String>()
          .toSet();
      _history = List.unmodifiable(
        m['historyVersion'] == 1
            ? (m['history'] as List? ?? []).map(
                (v) => DownloadHistoryEntry.fromJson(
                  Map<String, Object?>.from(v as Map),
                ),
              )
            : _records.map((r) => DownloadHistoryEntry.fromRecord(r)),
      );
    } catch (e) {
      throw AppFailure(FailureKind.storage, '下载记录损坏，原数据已保留', '$e');
    }
    if (m['historyVersion'] != 1) await _save(_records);
    await backend.initialize();
    _subscription = backend.updates.listen(
      (s) {
        unawaited(
          _queue.run(() => _merge(s)).catchError((Object e) {
            _note(e);
          }),
        );
      },
      onError: (Object e) {
        _note(e);
      },
    );
    await reconcile();
  }

  Future<void> _save(
    List<DownloadRecord> next, {
    List<DownloadHistoryEntry>? history,
    Set<String>? suppressed,
  }) async {
    final nextSuppressed = suppressed ?? _historySuppressed;
    final entries = {for (final h in history ?? _history) h.taskId: h};
    for (final record in next) {
      if (nextSuppressed.contains(record.taskId)) continue;
      final previous = entries[record.taskId];
      if (previous == null || previous.phase != record.phase) {
        entries[record.taskId] = DownloadHistoryEntry.fromRecord(
          record,
          finishedAt: previous?.finishedAt,
        );
      }
    }
    final nextHistory = entries.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    try {
      await store.write('downloads', {
        'records': next.map((r) => r.toJson()).toList(),
        'ignored': _ignored.toList(),
        'historyVersion': 1,
        'history': nextHistory.map((h) => h.toJson()).toList(),
        'historySuppressed': nextSuppressed.toList(),
      });
      storageFailure = null;
      _records = List.unmodifiable(next);
      _history = List.unmodifiable(nextHistory);
      _historySuppressed = nextSuppressed;
      _notify();
    } on AppFailure catch (e) {
      storageFailure = e;
      _notify();
      rethrow;
    }
  }

  DownloadRecord? _find(String id) =>
      _records.where((r) => r.taskId == id).firstOrNull;
  Future<void> _put(DownloadRecord value, {bool persist = true}) async {
    final next = _records
        .map((r) => r.taskId == value.taskId ? value : r)
        .toList();
    if (persist) {
      await _save(next);
    } else {
      _records = List.unmodifiable(next);
      _notify();
    }
  }

  Future<String> start(DownloadRequest request) =>
      _queue.run(() => _start(request));
  Future<String> _start(
    DownloadRequest request, {
    ParseCancellation? cancellation,
  }) async {
    final existing = _records
        .where((r) => !r.phase.terminal && r.request.url == request.url)
        .firstOrNull;
    if (existing != null) return existing.taskId;
    if (!['https', 'http'].contains(request.url.scheme) ||
        request.url.host.isEmpty) {
      throw const AppFailure(FailureKind.invalidLink, '没有可用的下载链接，请重新解析');
    }
    if (_find(request.taskId) != null || _ignored.contains(request.taskId)) {
      request = request.withId(newTaskId());
    }
    final record = DownloadRecord(
      request: request,
      phase: DownloadPhase.queued,
      createdAt: DateTime.now(),
    );
    await _save([record, ..._records]);
    if (cancellation?.isCancelled == true) {
      // The queue is still ours and native enqueue has not begun. Roll back
      // this provisional entry, including the history added by its first save.
      await _save(
        _records.where((r) => r.taskId != request.taskId).toList(),
        history: _history.where((h) => h.taskId != request.taskId).toList(),
      );
      throw const AppFailure(FailureKind.cancelled, '已取消重试');
    }
    AppFailure? enqueueError;
    try {
      await backend.enqueue(request);
    } on AppFailure catch (e) {
      enqueueError = e;
    }
    if (cancellation?.isCancelled == true) {
      await _cancelReplacement(record);
      throw const AppFailure(FailureKind.cancelled, '已取消重试');
    }
    final error = enqueueError;
    if (error != null) {
      await _put(record.copyWith(phase: DownloadPhase.failed, error: error));
      if (cancellation?.isCancelled == true) {
        await _cancelReplacement(record);
        throw const AppFailure(FailureKind.cancelled, '已取消重试');
      }
    }
    return request.taskId;
  }

  Future<void> _cancelReplacement(DownloadRecord record) async {
    await backend.cancel(record.taskId);
    final native = (await backend.snapshot())
        .where((s) => s.taskId == record.taskId)
        .firstOrNull;
    if (native?.savedFile != null) {
      // Native cancellation preserves any publication that already committed.
      // Recover its receipt before queued transfer events can replay.
      final file = native!.savedFile!;
      await _put(
        record.copyWith(
          phase: DownloadPhase.completed,
          savedFile: file,
          bytes: file.bytes,
          totalBytes: file.bytes,
          clearError: true,
        ),
      );
    } else {
      await _put(
        record.copyWith(phase: DownloadPhase.cancelled, clearError: true),
      );
    }
  }

  Future<void> _publish(DownloadRecord record) async {
    final pending = record.copyWith(
      phase: DownloadPhase.publishing,
      clearError: true,
    );
    await _put(pending);
    SavedFile file;
    try {
      file = await backend.publish(record.taskId);
    } on AppFailure catch (e) {
      // A complete staging file remains retryable; no terminal failure is emitted.
      await _put(pending.copyWith(error: e));
      return;
    }
    if (file.locator.isEmpty ||
        file.bytes <= 0 ||
        !file.mimeType.startsWith('video/')) {
      await _put(
        pending.copyWith(
          error: const AppFailure(FailureKind.storage, '公共文件回执无效'),
        ),
      );
      return;
    }
    // Persistence/observer failure must never turn a published file into failed.
    await _put(
      pending.copyWith(
        phase: DownloadPhase.completed,
        savedFile: file,
        clearError: true,
        bytes: file.bytes,
        totalBytes: file.bytes,
      ),
    );
  }

  Future<void> _merge(
    BackendTaskSnapshot s, {
    bool retryPublication = false,
  }) async {
    if (_ignored.contains(s.taskId)) return;
    var r = _find(s.taskId);
    if (r == null && s.request != null) {
      r = DownloadRecord(
        request: s.request!,
        phase: DownloadPhase.queued,
        createdAt: DateTime.now(),
      );
      await _save([r, ..._records]);
    }
    if (r == null) return;
    if (r.phase.terminal) {
      if (r.phase == DownloadPhase.cancelled &&
              s.phase == BackendPhase.transferred ||
          r.phase == DownloadPhase.completed &&
              s.phase == BackendPhase.failed) {
        _note('Ignored late ${s.phase.name} event for ${s.taskId}');
      }
      return;
    }
    switch (s.phase) {
      case BackendPhase.transferred:
        if (s.savedFile != null) {
          await _put(
            r.copyWith(
              phase: DownloadPhase.completed,
              savedFile: s.savedFile,
              clearError: true,
              bytes: s.savedFile!.bytes,
              totalBytes: s.savedFile!.bytes,
            ),
          );
        } else if (retryPublication || r.error == null) {
          await _publish(r);
        }
      case BackendPhase.failed:
        await _put(
          r.copyWith(
            phase: DownloadPhase.failed,
            error: s.error ?? const AppFailure(FailureKind.network, '下载失败，请重试'),
          ),
        );
      case BackendPhase.cancelled:
        await _put(
          r.copyWith(phase: DownloadPhase.cancelled, clearError: true),
        );
      case BackendPhase.queued:
      case BackendPhase.running:
        if (r.phase == DownloadPhase.publishing) return;
        final phase = s.phase == BackendPhase.running
            ? DownloadPhase.running
            : r.phase;
        if (phase != r.phase ||
            s.bytes != r.bytes ||
            s.totalBytes != r.totalBytes) {
          // Native transfer state recovers byte progress; only transitions need a JSON write.
          await _put(
            r.copyWith(phase: phase, bytes: s.bytes, totalBytes: s.totalBytes),
            persist: phase != r.phase,
          );
        }
    }
  }

  Future<void> cancel(String id) {
    _invalidateRetry(id);
    return _queue.run(() async {
      final r = _find(id);
      if (r == null || r.phase.terminal) return;
      await backend.cancel(id);
      final native = (await backend.snapshot())
          .where((s) => s.taskId == id)
          .firstOrNull;
      if (native?.savedFile != null) {
        await _merge(native!);
      } else {
        await _put(
          r.copyWith(phase: DownloadPhase.cancelled, clearError: true),
        );
      }
    });
  }

  Future<String> retry(String id) {
    final existing = _retries[id];
    if (existing != null) return existing.result.future;
    final pending = _PendingRetry();
    _retries[id] = pending;
    unawaited(
      _retry(id, pending)
          .then<void>(
            pending.result.complete,
            onError: (Object error, StackTrace stack) {
              pending.result.completeError(error, stack);
            },
          )
          .whenComplete(() {
            if (identical(_retries[id], pending)) _retries.remove(id);
          }),
    );
    return pending.result.future;
  }

  Future<String> _retry(String id, _PendingRetry pending) async {
    DownloadRecord? original;
    await _queue.run(() async {
      _checkRetry(pending);
      final record = _find(id);
      if (record == null) {
        throw const AppFailure(FailureKind.fileMissing, '下载记录不存在');
      }
      if (record.phase == DownloadPhase.publishing) {
        await _publish(record);
      } else if (record.phase == DownloadPhase.failed ||
          record.phase == DownloadPhase.cancelled) {
        original = record;
      }
    });
    final record = original;
    if (record == null) return id;
    var request = record.request;
    final refresh = refreshRequest;
    if (refresh != null && _shouldRefresh(record)) {
      // Parsing may wait for several sources. Keep native events and user
      // cancellation/deletion free to use the serialized persistence queue.
      request = await Future.any<DownloadRequest>([
        Future.sync(() => refresh(request, pending.cancellation)),
        pending.cancellation.whenCancelled.then(
          (_) => throw const AppFailure(FailureKind.cancelled, '已取消重试'),
        ),
      ]);
    }
    return _queue.run(() async {
      _checkRetry(pending);
      if (!identical(_find(id), record)) {
        throw const AppFailure(FailureKind.cancelled, '下载记录已变化，请重新重试');
      }
      return _start(
        request.withId(newTaskId()),
        cancellation: pending.cancellation,
      );
    });
  }

  bool _shouldRefresh(DownloadRecord record) {
    if (record.phase != DownloadPhase.failed ||
        record.request.postUrl == null) {
      return false;
    }
    final error = record.error;
    if (error == null ||
        [
          FailureKind.network,
          FailureKind.timeout,
          FailureKind.server,
        ].contains(error.kind)) {
      return true;
    }
    // Android currently maps DownloadManager failures to storage. Only its
    // explicit transfer reasons qualify; disk/publication failures do not.
    final match = RegExp(r'^系统下载失败\s*\((\d+)\)$')
        .firstMatch(error.details?.trim() ?? '');
    final reason = int.tryParse(match?.group(1) ?? '');
    return reason != null &&
        (reason >= 400 && reason <= 599 ||
            const [1000, 1002, 1004, 1005, 1008].contains(reason));
  }

  void _checkRetry(_PendingRetry pending) {
    if (_disposed || pending.cancellation.isCancelled) {
      throw const AppFailure(FailureKind.cancelled, '已取消重试');
    }
  }

  void _invalidateRetry(String id) {
    _retries.remove(id)?.cancellation.cancel();
  }

  Future<void> reconcile() => _queue.run(() async {
    final states = await backend.snapshot();
    for (final s in states) {
      await _merge(s, retryPublication: true);
    }
    final ids = states.map((s) => s.taskId).toSet();
    for (final r
        in _records
            .where(
              (r) => !r.phase.terminal && !r.legacy && !ids.contains(r.taskId),
            )
            .toList()) {
      await _put(
        r.copyWith(
          phase: DownloadPhase.failed,
          error: const AppFailure(FailureKind.network, '系统下载任务已丢失，请重试'),
        ),
      );
    }
  });
  Future<void> openDirectory() => backend.openDirectory();

  Future<T> _withFile<T>(String id, Future<T> Function(SavedFile) action) =>
      _queue.run(() async {
        final record = _find(id);
        final file = record?.savedFile;
        if (file == null) {
          throw const AppFailure(
            FailureKind.fileMissing,
            '这条记录无法定位文件，请在下载文件夹中查找',
          );
        }
        try {
          final result = await action(file);
          if (record!.error?.kind == FailureKind.fileMissing) {
            await _put(record.copyWith(clearError: true));
          }
          return result;
        } on AppFailure catch (e) {
          if (e.kind == FailureKind.fileMissing) {
            await _put(record!.copyWith(error: e));
          }
          rethrow;
        }
      });

  Future<void> open(String id, {void Function()? beforeOpen}) =>
      _withFile(id, (file) {
        beforeOpen?.call();
        return backend.open(file);
      });
  Future<SavedFile> fileForPreview(String id) => _withFile(id, (file) async {
    await backend.ensureReadable(file);
    return file;
  });
  Future<Uint8List?> thumbnail(String id) async {
    final record = _find(id);
    if (record == null) return null;
    final file = record.savedFile;
    final cache = coverCache;
    if (cache == null) {
      return file == null ? null : backend.thumbnailSavedFile(file);
    }
    final link =
        record.request.postUrl ??
        _history.where((h) => h.taskId == id).firstOrNull?.postUrl;
    final postId = PostLink.tryParse(link.toString())?.postId ?? id;
    if (file != null) {
      final data = await cache.get(
        record.request.mediaIndex == 1
            ? 'post:$postId'
            : 'video:${file.locator}',
        () => backend.thumbnailSavedFile(file),
      );
      if (data != null) return data;
    }
    final url = record.request.coverUrl;
    return url == null ? null : cache.remote('post:$postId', url);
  }

  Future<Uint8List?> favoriteCover(String postId, {Uri? coverUrl}) async {
    final cache = coverCache;
    if (cache == null) return null;
    if (coverUrl != null) {
      final data = await cache.remote('post:$postId', coverUrl);
      if (data != null) return data;
    }
    final historyIds = _history
        .where(
          (h) =>
              h.postUrl != null &&
              PostLink.tryParse(h.postUrl.toString())?.postId == postId,
        )
        .map((h) => h.taskId)
        .toSet();
    final matches = _records
        .where(
          (r) =>
              r.savedFile != null &&
              (historyIds.contains(r.taskId) ||
                  PostLink.tryParse(r.request.postUrl.toString())?.postId ==
                      postId),
        )
        .toList();
    final record =
        matches.where((r) => r.request.mediaIndex == 1).firstOrNull ??
        matches.firstOrNull;
    final data = await cache.get('post:$postId', () async {
      if (record == null) return null;
      return record.request.mediaIndex == 1
          ? backend.thumbnailSavedFile(record.savedFile!)
          : cache.get(
              'video:${record.savedFile!.locator}',
              () => backend.thumbnailSavedFile(record.savedFile!),
            );
    });
    final fallback = record?.request.coverUrl;
    return data != null || fallback == null || fallback == coverUrl
        ? data
        : cache.remote('post:$postId', fallback);
  }

  Future<void> _removeRecord(String id) async {
    final alreadyIgnored = _ignored.contains(id);
    _ignored.add(id);
    try {
      await _save(_records.where((r) => r.taskId != id).toList());
    } catch (_) {
      if (!alreadyIgnored) _ignored.remove(id);
      rethrow;
    }
  }

  Future<void> removeRecord(String id) {
    _invalidateRetry(id);
    return _queue.run(() async {
      final record = _find(id);
      if (record == null) return;
      if (!record.phase.terminal) {
        throw const AppFailure(FailureKind.storage, '请先取消正在下载的任务');
      }
      await _removeRecord(id);
    });
  }

  Future<void> deleteFile(String id) => _queue.run(() async {
    final record = _find(id);
    if (record == null) return;
    if (record.phase != DownloadPhase.completed || record.savedFile == null) {
      throw const AppFailure(FailureKind.storage, '这条记录没有可删除的已保存文件');
    }
    await backend.deleteSavedFile(record.savedFile!);
    await _removeRecord(id);
  });

  Future<void> clearCompletedHistory() {
    for (final id in _retries.keys.toList()) {
      if (_find(id)?.phase.terminal == true) _invalidateRetry(id);
    }
    return _queue.run(() async {
      final before = _ignored.toSet();
      _ignored.addAll(
        _records.where((r) => r.phase.terminal).map((r) => r.taskId),
      );
      try {
        await _save(_records.where((r) => !r.phase.terminal).toList());
      } catch (_) {
        _ignored
          ..clear()
          ..addAll(before);
        rethrow;
      }
    });
  }

  Future<void> removeHistory(String taskId) => _queue.run(
    () => _save(
      _records,
      history: _history.where((h) => h.taskId != taskId).toList(),
      suppressed: {..._historySuppressed, taskId},
    ),
  );

  Future<void> clearHistory() => _queue.run(
    () => _save(
      _records,
      history: [],
      suppressed: {
        ..._historySuppressed,
        ..._history.map((h) => h.taskId),
        ..._records.map((r) => r.taskId),
      },
    ),
  );
  @override
  void dispose() {
    _disposed = true;
    for (final pending in _retries.values) {
      pending.cancellation.cancel();
    }
    _retries.clear();
    unawaited(_subscription?.cancel());
    coverCache?.dispose();
    super.dispose();
  }
}

class _PendingRetry {
  final cancellation = ParseCancellation();
  final result = Completer<String>();
}
