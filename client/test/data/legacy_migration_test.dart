import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/data/legacy_migration.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/platform/legacy_data_gateway.dart';

Map<String, Object?> fixture({bool corrupt = false}) => {
  'sources': {
    'current': 'c_custom',
    'fallback': false,
    'custom': jsonEncode([
      {
        'id': 'c_custom',
        'name': '旧版自定义',
        'endpoint': 'https://source.test/?url={urlenc}',
        'kind': 'SCRAPE',
        'method': 'POST',
        'body': 'url={urlenc}',
      },
      if (corrupt) {'name': 'Broken', 'endpoint': 'file:///bad'},
    ]),
  },
  'settings': {'auto_clip': false},
  'historyJson': jsonEncode([
    {
      'name': '中文_123456_1280x720.mp4',
      'label': '1280x720',
      'bytes': 8,
      'tweet': 'https://x.com/a/status/123456',
      'time': 1770000000000,
    },
  ]),
};
void main() {
  late Directory temp;
  late SnapshotStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-migration-');
    store = SnapshotStore(temp);
  });
  tearDown(() async => temp.delete(recursive: true));
  LegacyDataGateway gateway(
    Map<String, Object?> old, {
    bool fileExists = false,
  }) => LegacyDataGateway(
    call: (method, args) async {
      if (method == 'readLegacy') return old;
      if (method == 'locateOwnedDownload') {
        return fileExists
            ? {
                'locator': 'content://media/external/downloads/1',
                'displayName': args['displayName'],
                'bytes': 8,
                'mimeType': 'video/mp4',
              }
            : null;
      }
      throw StateError(method);
    },
  );
  test('imports old settings, custom IDs and history idempotently', () async {
    final old = fixture();
    final before = jsonEncode(old);
    final migration = LegacyMigration(store, gateway(old, fileExists: true));
    final first = await migration.run();
    expect(first.errors, isEmpty);
    expect(first.imported, 2);
    final sources = await store.read('sources');
    expect(sources['current'], 'c_custom');
    expect(sources['fallback'], isFalse);
    expect((sources['custom'] as List).single['kind'], 'scrape');
    expect((await store.read('settings'))['autoClipboard'], isFalse);
    final history = (await store.read('downloads'))['records'] as List;
    expect(history, hasLength(1));
    final record = DownloadRecord.fromJson(
      Map<String, dynamic>.from(history.single as Map),
    );
    expect(record.savedFile?.locator, 'content://media/external/downloads/1');
    expect(record.legacy, isTrue);
    expect((await migration.run()).imported, 0);
    expect(jsonEncode(old), before);
  });
  test(
    'failed migration can be retried without clearing legacy data',
    () async {
      final old = fixture();
      final before = jsonEncode(old);
      await Directory('${temp.path}/downloads.json.tmp').create();
      final migration = LegacyMigration(store, gateway(old));
      final failed = await migration.run();
      expect(failed.errors, isNotEmpty);
      expect((await store.read('migration'))['completed'], isNot(true));
      await Directory('${temp.path}/downloads.json.tmp').delete();
      final retried = await migration.run();
      expect(retried.imported, 2);
      expect(retried.errors, isEmpty);
      expect((await store.read('sources'))['custom'] as List, hasLength(1));
      final records = (await store.read('downloads'))['records'] as List;
      expect(records, hasLength(1));
      expect(records.single['savedFile'], isNull);
      expect(jsonEncode(old), before);
    },
  );
  test(
    'corrupt entries are reported and do not mark migration complete',
    () async {
      final result = await LegacyMigration(
        store,
        gateway(fixture(corrupt: true)),
      ).run();
      expect(result.skipped, 1);
      expect(result.errors, isNotEmpty);
      expect((await store.read('migration'))['completed'], isFalse);
      expect((await store.read('downloads'))['records'] as List, hasLength(1));
    },
  );
  test('retry preserves newer Flutter choices and cleared history', () async {
    final first = LegacyMigration(store, gateway(fixture(corrupt: true)));
    await first.run();
    final sourceState = await store.read('sources');
    await store.write('sources', {
      ...sourceState,
      'current': 'vx',
      'fallback': true,
    });
    await store.write('settings', {
      'autoClipboard': true,
      'seedColor': 0xFF123456,
    });
    final downloads = await store.read('downloads');
    final id =
        ((downloads['records'] as List).single as Map)['request']['taskId'];
    await store.write('downloads', {
      'records': [],
      'ignored': [id],
    });
    await first.run();
    expect((await store.read('sources'))['current'], 'vx');
    expect((await store.read('settings'))['autoClipboard'], isTrue);
    expect((await store.read('downloads'))['records'] as List, isEmpty);
  });
}
