import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/fake_download_backend.dart';

DownloadRequest request(String id, {String url = 'a'}) => DownloadRequest(
  taskId: id,
  url: Uri.parse('https://video.twimg.com/$url.mp4'),
  displayName: '$url.mp4',
  headers: const {},
  mediaIndex: 1,
);
void main() {
  test(
    'native task metadata recovers an entry missing from the JSON snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('xdl-orphan-');
      final store = SnapshotStore(Directory('${dir.path}/snapshots'));
      final backend = FakeDownloadBackend(dir);
      backend.state['orphan'] = BackendTaskSnapshot(
        taskId: 'orphan',
        phase: BackendPhase.transferred,
        bytes: 8,
        request: request('orphan'),
      );
      final repo = DownloadRepository(store: store, backend: backend);
      try {
        await repo.initialize();
        expect(repo.records.single.phase, DownloadPhase.completed);
        await repo.clearCompletedHistory();
        await repo.reconcile();
        expect(
          repo.records,
          isEmpty,
          reason: 'cleared native entries must not reappear',
        );
      } finally {
        repo.dispose();
        await backend.close();
        await dir.delete(recursive: true);
      }
    },
  );
  late Directory temp;
  late SnapshotStore store;
  late FakeDownloadBackend backend;
  late DownloadRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-repo-');
    store = SnapshotStore(Directory('${temp.path}/snapshots'));
    backend = FakeDownloadBackend(temp);
    repo = DownloadRepository(store: store, backend: backend);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await backend.close();
    await temp.delete(recursive: true);
  });
  void complete(String id) => backend.emit(
    BackendTaskSnapshot(taskId: id, phase: BackendPhase.transferred, bytes: 8),
  );
  test('internal preview resolves its saved receipt and marks missing files without external launch', () async {
    await repo.start(request('a'));
    complete('a');
    await repo.reconcile();
    final saved = await repo.fileForPreview('a');
    expect(saved.locator, repo.records.single.savedFile!.locator);
    await File(saved.locator).delete();
    await expectLater(
      repo.fileForPreview('a'),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.fileMissing,
        ),
      ),
    );
    expect(repo.records.single.error?.kind, FailureKind.fileMissing);
  });
  test(
    'deleting one public file is durable and leaves other files untouched',
    () async {
      for (final id in ['a', 'b']) {
        await repo.start(request(id, url: id));
        complete(id);
      }
      await repo.reconcile();
      final deleted = repo.records
          .firstWhere((r) => r.taskId == 'a')
          .savedFile!;
      final kept = repo.records.firstWhere((r) => r.taskId == 'b').savedFile!;
      await repo.deleteFile('a');
      await repo.reconcile();
      expect(await File(deleted.locator).exists(), isFalse);
      expect(await File(kept.locator).exists(), isTrue);
      repo.dispose();
      repo = DownloadRepository(store: store, backend: backend);
      await repo.initialize();
      expect(repo.records.single.taskId, 'b');
    },
  );
  test(
    'removing one record preserves its file and refuses active tasks',
    () async {
      await repo.start(request('a'));
      complete('a');
      await repo.reconcile();
      final saved = repo.records.single.savedFile!;
      await repo.removeRecord('a');
      await repo.reconcile();
      expect(repo.records, isEmpty);
      expect(await File(saved.locator).exists(), isTrue);
      await repo.start(request('active', url: 'b'));
      await expectLater(
        repo.removeRecord('active'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(repo.deleteFile('active'), throwsA(isA<AppFailure>()));
      expect(repo.records.single.taskId, 'active');
    },
  );
  test(
    'delete failure keeps the record and an already absent file can be removed',
    () async {
      await repo.start(request('a'));
      complete('a');
      await repo.reconcile();
      final saved = repo.records.single.savedFile!;
      backend.failDeletion = true;
      await expectLater(repo.deleteFile('a'), throwsA(isA<AppFailure>()));
      expect(repo.records.single.taskId, 'a');
      expect(await File(saved.locator).exists(), isTrue);
      backend.failDeletion = false;
      await File(saved.locator).delete();
      await expectLater(repo.open('a'), throwsA(isA<AppFailure>()));
      expect(repo.records.single.error?.kind, FailureKind.fileMissing);
      await repo.deleteFile('a');
      await repo.reconcile();
      expect(repo.records, isEmpty);
    },
  );
  test('deduplicates concurrent active URL', () async {
    final ids = await Future.wait([
      repo.start(request('first')),
      repo.start(request('sameUrl')),
    ]);
    expect(ids.toSet(), hasLength(1));
    expect(repo.records, hasLength(1));
    expect(backend.enqueued, hasLength(1));
    complete(ids.first);
    await repo.reconcile();
    expect(repo.records.single.phase, DownloadPhase.completed);
  });
  test('late terminal events cannot overwrite a new active task', () async {
    await repo.start(request('old'));
    await repo.cancel('old');
    final next = await repo.start(request('new'));
    complete('old');
    await repo.reconcile();
    expect(
      repo.records.firstWhere((r) => r.taskId == 'old').phase,
      DownloadPhase.cancelled,
    );
    expect((await repo.start(request('third'))), next);
  });
  test('two simultaneous completions remain durable and observer failure is isolated', () async {
    await repo.start(request('a'));
    await repo.start(request('b', url: 'b'));
    final original = FlutterError.onError;
    FlutterError.onError = (_) {};
    repo.addListener(() {
      throw StateError('observer failed');
    });
    try {
      complete('a');
      complete('b');
      await repo.reconcile();
    } finally {
      FlutterError.onError = original;
    }
    expect(
      repo.records.every((r) => r.phase == DownloadPhase.completed),
      isTrue,
    );
    expect((await store.read('downloads'))['records'] as List, hasLength(2));
    expect(backend.publications, 2);
  });
  test(
    'publishing errors preserve a retryable task without a false terminal',
    () async {
      backend.failPublication = true;
      await repo.start(request('a'));
      complete('a');
      await repo.reconcile();
      expect(repo.records.single.phase, DownloadPhase.publishing);
      expect(repo.records.single.error?.kind, FailureKind.storage);
      backend.failPublication = false;
      await repo.retry('a');
      expect(repo.records.single.phase, DownloadPhase.completed);
      expect(backend.enqueued, hasLength(1));
    },
  );
  test(
    'restart recovers publishing once; deleted file has a clear error',
    () async {
      final record = DownloadRecord(
        request: request('a'),
        phase: DownloadPhase.publishing,
        createdAt: DateTime(2026),
      );
      await store.write('downloads', {
        'records': [record.toJson()],
      });
      backend.state['a'] = const BackendTaskSnapshot(
        taskId: 'a',
        phase: BackendPhase.transferred,
        bytes: 8,
      );
      repo.dispose();
      repo = DownloadRepository(store: store, backend: backend);
      await repo.initialize();
      expect(repo.records.single.phase, DownloadPhase.completed);
      expect(backend.publications, 1);
      await repo.reconcile();
      expect(backend.publications, 1);
      await File(repo.records.single.savedFile!.locator).delete();
      await expectLater(
        repo.open('a'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.fileMissing,
          ),
        ),
      );
    },
  );
  test('clear history retains active tasks and public files', () async {
    await repo.start(request('a'));
    complete('a');
    await repo.reconcile();
    final file = repo.records.single.savedFile!;
    await repo.start(request('b', url: 'b'));
    await repo.clearCompletedHistory();
    expect(repo.records.single.taskId, 'b');
    expect(await File(file.locator).exists(), isTrue);
  });
  test(
    'metadata write failure after publication recovers without a false failure',
    () async {
      await repo.start(request('a'));
      backend.afterPublication = () async {
        await Directory('${temp.path}/snapshots/downloads.json.tmp').create();
      };
      complete('a');
      await expectLater(repo.reconcile(), throwsA(isA<AppFailure>()));
      expect(repo.records.single.phase, DownloadPhase.publishing);
      expect(backend.saved['a'], isNotNull);
      await Directory('${temp.path}/snapshots/downloads.json.tmp').delete();
      backend.afterPublication = null;
      await repo.reconcile();
      expect(repo.records.single.phase, DownloadPhase.completed);
      expect(backend.publications, 1);
    },
  );
}
