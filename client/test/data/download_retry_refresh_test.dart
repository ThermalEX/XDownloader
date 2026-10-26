import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/fake_download_backend.dart';

DownloadRequest oldRequest({String id = 'old', bool hasPost = true}) =>
    DownloadRequest(
      taskId: id,
      url: Uri.parse('https://video.example/expired-$id.mp4'),
      displayName: 'original-name.mp4',
      headers: const {'referer': 'https://x.com/'},
      mediaIndex: 2,
      postUrl: hasPost ? Uri.parse('https://x.com/author/status/123456') : null,
      width: 1280,
      height: 720,
    );

DownloadRequest refreshed(DownloadRequest old) => DownloadRequest(
  taskId: old.taskId,
  url: Uri.parse('https://video.example/fresh.mp4'),
  displayName: old.displayName,
  headers: old.headers,
  mediaIndex: old.mediaIndex,
  postUrl: old.postUrl,
  width: 1280,
  height: 720,
);

class DelayedRetryStore extends SnapshotStore {
  DelayedRetryStore(super.directory);

  Future<void> Function(Map<String, Object?>)? beforeWrite;

  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    await beforeWrite?.call(data);
    await super.write(key, data);
  }
}

class DelayedRetryBackend extends FakeDownloadBackend {
  DelayedRetryBackend(super.directory);

  Future<void> Function(DownloadRequest)? afterEnqueue;

  @override
  Future<void> enqueue(DownloadRequest request) async {
    await super.enqueue(request);
    await afterEnqueue?.call(request);
  }

  @override
  Future<void> cancel(String id) async {
    final file = saved[id];
    if (file == null) return super.cancel(id);
    emit(
      BackendTaskSnapshot(
        taskId: id,
        phase: BackendPhase.transferred,
        bytes: file.bytes,
        savedFile: file,
      ),
    );
  }
}

void main() {
  late Directory directory;
  late DelayedRetryStore store;
  late DelayedRetryBackend backend;
  late DownloadRepository repo;
  late Future<DownloadRequest> Function(DownloadRequest, ParseCancellation)
  refresh;
  var disposed = false;
  var calls = 0;

  setUp(() async {
    calls = 0;
    disposed = false;
    directory = await Directory.systemTemp.createTemp('retry-refresh-');
    store = DelayedRetryStore(Directory('${directory.path}/snapshots'));
    backend = DelayedRetryBackend(directory);
    refresh = (request, cancellation) async {
      calls++;
      return refreshed(request);
    };
    repo = DownloadRepository(
      store: store,
      backend: backend,
      refreshRequest: (request, cancellation) => refresh(request, cancellation),
    );
    await repo.initialize();
  });

  tearDown(() async {
    if (!disposed) repo.dispose();
    await backend.close();
    await directory.delete(recursive: true);
  });

  Future<void> fail({AppFailure? error, bool hasPost = true}) async {
    await repo.start(oldRequest(hasPost: hasPost));
    backend.emit(
      BackendTaskSnapshot(
        taskId: 'old',
        phase: BackendPhase.failed,
        bytes: 0,
        error: error ?? const AppFailure(FailureKind.network, '下载失败'),
      ),
    );
    await repo.reconcile();
  }

  for (final status in [401, 403, 404, 410]) {
    test(
      'explicit retry refreshes native HTTP $status and retains old history',
      () async {
        await fail(
          error: AppFailure(FailureKind.storage, '下载未完成', '系统下载失败 ($status)'),
        );
        final nextId = await repo.retry('old');
        expect(nextId, isNot('old'));
        expect(calls, 1);
        expect(
          backend.enqueued.last.url.toString(),
          'https://video.example/fresh.mp4',
        );
        expect(backend.enqueued.last.displayName, 'original-name.mp4');
        expect(
          repo.records.firstWhere((r) => r.taskId == 'old').phase,
          DownloadPhase.failed,
        );
        expect(repo.history.map((h) => h.taskId), containsAll(['old', nextId]));
      },
    );
  }

  test('failed refresh never silently retries the expired URL', () async {
    await fail();
    refresh = (_, _) async =>
        throw const AppFailure(FailureKind.noVideo, '原帖子已不可用');
    await expectLater(repo.retry('old'), throwsA(isA<AppFailure>()));
    expect(backend.enqueued, hasLength(1));
    expect(repo.records.single.phase, DownloadPhase.failed);
  });

  test('duplicate retries share the refresh and create one new task', () async {
    await fail();
    final entered = Completer<void>();
    final response = Completer<DownloadRequest>();
    refresh = (request, cancellation) {
      calls++;
      entered.complete();
      return response.future;
    };
    final first = repo.retry('old');
    final second = repo.retry('old');
    await entered.future;
    response.complete(refreshed(oldRequest()));
    expect(await first, await second);
    expect(calls, 1);
    expect(backend.enqueued, hasLength(2));
  });

  for (final action in ['cancel', 'remove', 'clear', 'dispose']) {
    test('$action during replacement write prevents native enqueue', () async {
      await fail();
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeWrite = (data) async {
        final records = data['records'] as List;
        if (records.length > 1 && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final result = repo.retry('old');
      Object? retryError;
      final settled = result.then<void>(
        (_) {},
        onError: (Object error) {
          retryError = error;
        },
      );
      await entered.future;
      Future<void>? mutation;
      switch (action) {
        case 'cancel':
          mutation = repo.cancel('old');
        case 'remove':
          mutation = repo.removeRecord('old');
        case 'clear':
          mutation = repo.clearCompletedHistory();
        case 'dispose':
          repo.dispose();
          disposed = true;
      }
      release.complete();
      await settled;
      await mutation;
      expect(backend.enqueued, hasLength(1));
      expect(
        retryError,
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      );
      expect(repo.records.every((r) => r.phase.terminal), isTrue);
      expect(repo.history.map((h) => h.taskId), everyElement('old'));
      final snapshot = await store.read('downloads');
      final savedRecords = (snapshot['records'] as List).map(
        (r) => DownloadRecord.fromJson(Map<String, dynamic>.from(r as Map)),
      );
      expect(savedRecords.every((r) => r.phase.terminal), isTrue);
      expect(savedRecords.map((r) => r.taskId), everyElement('old'));
    });

    test(
      '$action invalidates pending refresh without blocking other events',
      () async {
        await fail();
        await repo.start(oldRequest(id: 'other'));
        final entered = Completer<ParseCancellation>();
        final response = Completer<DownloadRequest>();
        refresh = (_, cancellation) {
          entered.complete(cancellation);
          return response.future;
        };
        final result = repo.retry('old');
        final cancelled = expectLater(
          result,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.cancelled,
            ),
          ),
        );
        final cancellation = await entered.future;
        backend.emit(
          const BackendTaskSnapshot(
            taskId: 'other',
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
        await repo.reconcile().timeout(const Duration(seconds: 2));
        final file = repo.records
            .firstWhere((r) => r.taskId == 'other')
            .savedFile!;
        expect(await File(file.locator).exists(), isTrue);
        switch (action) {
          case 'cancel':
            await repo.cancel('old').timeout(const Duration(seconds: 2));
          case 'remove':
            await repo.removeRecord('old').timeout(const Duration(seconds: 2));
          case 'clear':
            await repo.clearCompletedHistory().timeout(
              const Duration(seconds: 2),
            );
          case 'dispose':
            repo.dispose();
            disposed = true;
        }
        expect(cancellation.isCancelled, isTrue);
        await cancelled.timeout(const Duration(seconds: 2));
        response.complete(refreshed(oldRequest()));
        await Future<void>.delayed(Duration.zero);
        expect(backend.enqueued, hasLength(2));
        expect(await File(file.locator).exists(), isTrue);
      },
    );
  }

  for (final published in [false, true]) {
    test(
      'cancel during native enqueue ${published ? 'preserves public receipt' : 'cancels replacement'}',
      () async {
        await fail();
        final entered = Completer<DownloadRequest>();
        final release = Completer<void>();
        backend.afterEnqueue = (request) async {
          entered.complete(request);
          await release.future;
        };
        Object? retryError;
        final settled = repo
            .retry('old')
            .then<void>(
              (_) {},
              onError: (Object error) {
                retryError = error;
              },
            );
        final replacement = await entered.future;
        SavedFile? file;
        if (published) file = await backend.publish(replacement.taskId);
        final cancelling = repo.cancel('old');
        release.complete();
        await settled;
        await cancelling;
        await repo.reconcile();
        expect(
          retryError,
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        );
        final record = repo.records.firstWhere(
          (r) => r.taskId == replacement.taskId,
        );
        expect(
          record.phase,
          published ? DownloadPhase.completed : DownloadPhase.cancelled,
        );
        expect(
          backend.state[replacement.taskId]!.phase,
          published ? BackendPhase.transferred : BackendPhase.cancelled,
        );
        if (file != null) {
          expect(record.savedFile?.locator, file.locator);
          expect(await File(file.locator).exists(), isTrue);
        }
      },
    );
  }

  test('cancelled retry keeps existing direct retry behavior', () async {
    await repo.start(oldRequest());
    await repo.cancel('old');
    await repo.retry('old');
    expect(calls, 0);
    expect(backend.enqueued.last.url, oldRequest().url);
  });

  test('missing-post retry keeps existing direct retry behavior', () async {
    await fail(hasPost: false);
    await repo.retry('old');
    expect(calls, 0);
    expect(backend.enqueued.last.url, oldRequest().url);
  });

  for (final reason in ['磁盘空间不足', '系统下载失败 (1006)']) {
    test('disk failure $reason does not trigger a reparse', () async {
      await fail(error: AppFailure(FailureKind.storage, '下载未完成', reason));
      await repo.retry('old');
      expect(calls, 0);
    });
  }

  test(
    'publication retry publishes the staging file with the same task ID',
    () async {
      backend.failPublication = true;
      await repo.start(oldRequest());
      backend.emit(
        const BackendTaskSnapshot(
          taskId: 'old',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await repo.reconcile();
      backend.failPublication = false;
      expect(await repo.retry('old'), 'old');
      expect(repo.records.single.phase, DownloadPhase.completed);
      expect(calls, 0);
      expect(backend.enqueued, hasLength(1));
    },
  );
}
