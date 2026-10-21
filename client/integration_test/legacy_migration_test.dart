import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/data/legacy_migration.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/platform/download_backend.dart';
import 'package:xdownloader/platform/legacy_data_gateway.dart';
import 'package:xdownloader/platform/platform_bridge.dart';
import 'package:xdownloader/platform/share_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('reads same-package legacy preferences without modifying them', (
    _,
  ) async {
    final before = await callPlatform('readLegacy', {}) as Map;
    final fileId = newTaskId();
    final savedName = 'xdl_probe_$fileId.mp4';
    final fixture = {
      'sources': {
        'current': 'c_probe',
        'fallback': false,
        'custom': jsonEncode([
          {
            'id': 'c_probe',
            'name': 'Probe',
            'endpoint': 'https://source.test/?url={urlenc}',
            'kind': 'SCRAPE',
            'method': 'GET',
            'body': '',
          },
        ]),
      },
      'settings': {'auto_clip': false},
      'historyJson': jsonEncode([
        {
          'name': savedName,
          'label': '1280x720',
          'bytes': 8,
          'tweet': 'https://x.com/a/status/123456',
          'time': 1770000000000,
        },
      ]),
    };
    final support = await callPlatform('supportDirectory', {}) as String;
    final directory = Directory('$support/xdl_migration_probe_${newTaskId()}');
    try {
      await callPlatform('probeSeed', {
        'taskId': fileId,
        'displayName': savedName,
        'data': base64Encode([
          0,
          0,
          0,
          24,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
          0,
          0,
          0,
          0,
          105,
          115,
          111,
          109,
          109,
          112,
          52,
          50,
        ]),
        'statusCode': 200,
        'mimeType': 'video/mp4',
        'forceFailure': false,
      });
      final saved = await callPlatform('publish', {'taskId': fileId}) as Map;
      await callPlatform(
        'probeReplaceLegacy',
        Map<String, Object?>.from(fixture),
      );
      final nativeBefore = await callPlatform('readLegacy', {});
      final store = SnapshotStore(directory);
      final result = await LegacyMigration(store, LegacyDataGateway()).run();
      expect(result.errors, isEmpty);
      expect(result.imported, 2);
      expect((await store.read('sources'))['current'], 'c_probe');
      expect((await store.read('settings'))['autoClipboard'], isFalse);
      final records = (await store.read('downloads'))['records'] as List;
      expect(records.single['savedFile']['locator'], saved['locator']);
      expect(
        await LegacyDataGateway().locateOwnedDownload(
          'xdl_probe_missing_$fileId.mp4',
        ),
        isNull,
      );
      expect(await callPlatform('readLegacy', {}), nativeBefore);
      expect(
        (await LegacyMigration(store, LegacyDataGateway()).run()).imported,
        0,
      );
    } finally {
      await callPlatform('probeDelete', {'taskId': fileId});
      await callPlatform(
        'probeReplaceLegacy',
        Map<String, Object?>.from(before),
      );
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
  testWidgets(
    'cold queue is consumed once and Android onNewIntent delivers a hot share',
    (_) async {
      await callPlatform('probePrepareInitialShare', {
        'text': 'https://x.com/a/status/123456',
      });
      final gateway = ShareGateway();
      expect(await gateway.initialText(), 'https://x.com/a/status/123456');
      expect(await callPlatform('initialShare', {}), isNull);
      final hot = gateway.sharedText.first;
      await callPlatform('probeSendShare', {
        'text': 'https://x.com/b/status/222222',
      });
      expect(
        await hot.timeout(const Duration(seconds: 5)),
        'https://x.com/b/status/222222',
      );
      expect(await callPlatform('initialShare', {}), isNull);
      await callPlatform('probePrepareInitialShare', {'text': ''});
      expect(await callPlatform('initialShare', {}), isNull);
    },
  );
}
