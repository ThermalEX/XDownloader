import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/core/models/download.dart';

import '../support/fake_download_backend.dart';

void main() {
  late Directory temp;
  late SnapshotStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-snapshot-');
    store = SnapshotStore(temp);
  });
  tearDown(() async => temp.delete(recursive: true));
  for (final key in ['settings', 'sources', 'downloads']) {
    test(
      'repository recovers $key payload damage and preserves valid backup',
      () async {
        final good = switch (key) {
          'settings' => <String, Object?>{'seedColor': 0xFF47658A},
          'sources' => <String, Object?>{
            'current': 'fx',
            'custom': [],
            'fallback': false,
          },
          _ => <String, Object?>{
            'records': [
              DownloadRecord(
                request: DownloadRequest(
                  taskId: 'a',
                  url: Uri.parse('https://video.test/a.mp4'),
                  displayName: 'a.mp4',
                  headers: const {},
                  mediaIndex: 1,
                ),
                phase: DownloadPhase.cancelled,
                createdAt: DateTime(2026),
              ).toJson(),
            ],
          },
        };
        await store.write(key, good);
        await store.write(key, good);
        final broken = switch (key) {
          'settings' => {'seedColor': 'broken'},
          'sources' => {'custom': 'broken'},
          _ => {
            'records': ['broken'],
          },
        };
        await File('${temp.path}/$key.json')
            .writeAsString(jsonEncode({'version': 1, 'data': broken}));
        if (key == 'settings') {
          final repo = SettingsRepository(store);
          await repo.initialize();
          expect(repo.value.seedColor, 0xFF47658A);
          repo.dispose();
        }
        if (key == 'sources') {
          final repo = SourceRepository(store);
          await repo.initialize();
          expect(repo.currentId, 'fx');
          expect(repo.autoFallback, isFalse);
          repo.dispose();
        }
        if (key == 'downloads') {
          final backend = FakeDownloadBackend(temp);
          final repo = DownloadRepository(store: store, backend: backend);
          try {
            await repo.initialize();
            expect(repo.records.single.taskId, 'a');
          } finally {
            repo.dispose();
            await backend.close();
          }
        }
        // A repository may migrate a recovered snapshot before the next write.
        final recovered = await store.read(key);
        await store.write(key, good);
        expect(
          (jsonDecode(await File('${temp.path}/$key.json.bak').readAsString())
              as Map)['data'],
          recovered,
        );
      },
    );
  }
  test('writes versioned snapshots and recovers valid backup', () async {
    await store.write('sources', {'current': 'fx'});
    await store.write('sources', {'current': 'vx'});
    expect(
      jsonDecode(
        await File('${temp.path}/sources.json').readAsString(),
      )['version'],
      1,
    );
    await File('${temp.path}/sources.json').writeAsString('{broken');
    expect((await store.read('sources'))['current'], 'fx');
    await store.write('sources', {'current': 'xdl'});
    expect((await store.read('sources'))['current'], 'xdl');
  });
  test('failed write keeps the previous durable snapshot', () async {
    await store.write('settings', {'autoClipboard': false});
    await Directory('${temp.path}/settings.json.tmp').create();
    await expectLater(
      store.write('settings', {'autoClipboard': true}),
      throwsA(isA<AppFailure>()),
    );
    expect((await store.read('settings'))['autoClipboard'], isFalse);
  });
  test(
    'corrupt snapshots are reported rather than silently resetting',
    () async {
      await File('${temp.path}/sources.json').writeAsString('bad');
      await expectLater(store.read('sources'), throwsA(isA<AppFailure>()));
      expect(await store.read('fresh'), isEmpty);
    },
  );
}
