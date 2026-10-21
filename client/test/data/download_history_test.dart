import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/fake_download_backend.dart';

class FailingHistoryStore extends SnapshotStore {
  FailingHistoryStore(super.directory);
  bool fail = false;
  int writes = 0;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (fail) {
      throw const AppFailure(FailureKind.storage, 'test storage failure');
    }
    writes++;
    await super.write(key, data);
  }
}

DownloadRequest historyRequest(String id) => DownloadRequest(
  taskId: id,
  url: Uri.parse('https://video.twimg.com/$id.mp4'),
  displayName: '$id.mp4',
  headers: const {'private': 'not-in-history'},
  mediaIndex: 1,
  postUrl: Uri.parse('https://x.com/author/status/123456'),
);

void main() {
  late Directory temp;
  late FailingHistoryStore store;
  late FakeDownloadBackend backend;
  late DownloadRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-history-');
    store = FailingHistoryStore(Directory('${temp.path}/snapshots'));
    backend = FakeDownloadBackend(temp);
    repo = DownloadRepository(store: store, backend: backend);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await backend.close();
    await temp.delete(recursive: true);
  });
  Future<void> complete(String id) async {
    backend.emit(
      BackendTaskSnapshot(
        taskId: id,
        phase: BackendPhase.transferred,
        bytes: 8,
      ),
    );
    await repo.reconcile();
  }

  Future<void> restart() async {
    repo.dispose();
    repo = DownloadRepository(store: store, backend: backend);
    await repo.initialize();
  }

  test('migrates_old_records_once', () async {
    final old = DownloadRecord(
      request: historyRequest('old'),
      phase: DownloadPhase.completed,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 21),
    );
    await store.write('downloads', {
      'records': [old.toJson()],
      'ignored': <String>[],
    });
    await restart();
    expect(repo.history.single.taskId, 'old');
    expect(repo.history.single.finishedAt, old.updatedAt);
    await repo.clearHistory();
    await restart();
    expect(repo.history, isEmpty);
    expect(repo.records, hasLength(1));
  });
  test('history_survives_file_and_record_removal', () async {
    await repo.start(historyRequest('a'));
    await complete('a');
    await repo.deleteFile('a');
    expect(repo.records, isEmpty);
    expect(repo.history.single.postUrl, historyRequest('a').postUrl);
    await repo.start(historyRequest('b'));
    await repo.cancel('b');
    await repo.removeRecord('b');
    await restart();
    expect(repo.history, hasLength(2));
    final raw = (await store.read('downloads'))['history'].toString();
    expect(raw, isNot(contains('not-in-history')));
    expect(raw, isNot(contains('video.twimg.com')));
  });
  test(
    'cleared_running_history_stays_deleted_after_completion_and_restart',
    () async {
      await repo.start(historyRequest('a'));
      await repo.clearHistory();
      await complete('a');
      await restart();
      expect(repo.history, isEmpty);
      expect(repo.records.single.phase, DownloadPhase.completed);
      expect(
        await File(repo.records.single.savedFile!.locator).exists(),
        isTrue,
      );
    },
  );
  test('failure_cancel_retry_and_duplicate_events_preserve_end_time', () async {
    await repo.start(historyRequest('a'));
    backend.emit(
      const BackendTaskSnapshot(
        taskId: 'a',
        phase: BackendPhase.failed,
        bytes: 0,
      ),
    );
    await repo.reconcile();
    final finished = repo.history.single.finishedAt;
    expect(finished, isNotNull);
    await repo.reconcile();
    expect(repo.history.single.finishedAt, finished);
    final next = await repo.retry('a');
    expect(next, isNot('a'));
    await repo.cancel(next);
    expect(repo.history, hasLength(2));
    expect(repo.history.first.phase, DownloadPhase.cancelled);
  });
  test('progress_does_not_write_history_each_tick', () async {
    await repo.start(historyRequest('a'));
    backend.emit(
      const BackendTaskSnapshot(
        taskId: 'a',
        phase: BackendPhase.running,
        bytes: 1,
      ),
    );
    await repo.reconcile();
    final before = store.writes;
    backend.emit(
      const BackendTaskSnapshot(
        taskId: 'a',
        phase: BackendPhase.running,
        bytes: 2,
      ),
    );
    await repo.reconcile();
    expect(store.writes, before);
  });
  test('failed_history_write_keeps_memory_and_file', () async {
    await repo.start(historyRequest('a'));
    await complete('a');
    store.fail = true;
    await expectLater(repo.clearHistory(), throwsA(isA<AppFailure>()));
    expect(repo.history, hasLength(1));
    await expectLater(repo.deleteFile('a'), throwsA(isA<AppFailure>()));
    expect(repo.history, hasLength(1));
    store.fail = false;
    await repo.deleteFile('a');
    await restart();
    expect(repo.history, hasLength(1));
    expect(repo.records, isEmpty);
  });
  test('corrupt_history_uses_valid_backup', () async {
    await repo.start(historyRequest('a'));
    await complete('a');
    final data = await store.read('downloads');
    await store.write('downloads', {
      ...data,
      'history': [
        {'bad': true},
      ],
    });
    await restart();
    expect(repo.history.single.taskId, 'a');
  });
  test('single_removed_history_is_not_revived_by_native_recovery', () async {
    await repo.start(historyRequest('a'));
    await repo.removeHistory('a');
    await complete('a');
    await repo.removeRecord('a');
    await restart();
    expect(repo.history, isEmpty);
    expect(backend.saved, contains('a'));
  });
}
