import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/platform/android_download_backend.dart';
import 'package:xdownloader/platform/download_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = AndroidDownloadBackend.channel;
  Future<dynamic> call(String method, [Map<String, Object?> args = const {}]) =>
      channel.invokeMethod(method, args);
  final owned = <String>[];
  final mp4 = <int>[
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
  ];
  Future<String> seed({
    List<int>? bytes,
    int status = 200,
    String mime = 'video/mp4',
    bool fail = false,
  }) async {
    final id = newTaskId();
    owned.add(id);
    await call('probeSeed', {
      'taskId': id,
      'displayName': 'xdl_probe_$id.mp4',
      'data': base64Encode(bytes ?? mp4),
      'statusCode': status,
      'mimeType': mime,
      'forceFailure': fail,
    });
    return id;
  }

  tearDown(() async {
    for (final id in owned) {
      await call('probeDelete', {'taskId': id});
    }
    owned.clear();
    await call('probeCleanupOrphanFixtures');
  });
  testWidgets(
    'template emoji boundary survives native naming and publication',
    (_) async {
      final id = newTaskId();
      owned.add(id);
      final backend = AndroidDownloadBackend();
      final base = 'xdl_probe_${'a' * 139}😀';
      final expected = '${base}_$id.mp4';
      try {
        await backend.enqueue(
          DownloadRequest(
            taskId: id,
            url: Uri.parse(
              'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16',
            ),
            displayName: '$base.mp4',
            headers: const {},
            mediaIndex: 1,
          ),
        );
        final record = (await call('rawSnapshot') as List)
            .cast<Map>()
            .firstWhere((r) => r['taskId'] == id);
        expect(record['displayName'], expected);
        expect(utf8.encode(expected).length, lessThanOrEqualTo(213));
        SavedFile? saved;
        for (var i = 0; i < 30 && saved == null; i++) {
          final current = (await backend.snapshot()).firstWhere(
            (r) => r.taskId == id,
          );
          saved = current.savedFile;
          if (saved == null) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        expect(saved?.displayName, expected);
        expect(saved?.bytes, 354883);
      } finally {
        await backend.close();
      }
    },
  );
  testWidgets(
    'native deletion removes only its public file and tolerates missing files',
    (_) async {
      final backend = AndroidDownloadBackend();
      try {
        final first = await seed(), second = await seed();
        final deleted = await backend.publish(first);
        await backend.publish(second);
        await backend.deleteSavedFile(deleted);
        await expectLater(
          backend.open(deleted),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              FailureKind.fileMissing,
            ),
          ),
        );
        expect(
          base64Decode(
            (await call('probeInspect', {'taskId': second}) as Map)['data']
                as String,
          ),
          mp4,
        );
        await backend.deleteSavedFile(deleted);
        await expectLater(
          backend.deleteSavedFile(
            const SavedFile(
              locator: 'content://settings/system/123',
              displayName: 'unsupported.mp4',
              bytes: 8,
              mimeType: 'video/mp4',
            ),
          ),
          throwsA(isA<AppFailure>()),
        );
      } finally {
        await backend.close();
      }
    },
  );
  testWidgets('interrupted enqueue after system acceptance restores its ID', (
    _,
  ) async {
    final id = newTaskId();
    owned.add(id);
    final backend = AndroidDownloadBackend();
    try {
      await call('probeInterruptEnqueue', {
        'taskId': id,
        'url': 'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16',
        'displayName': 'xdl_probe_$id.mp4',
        'headers': <String, String>{},
        'mediaIndex': 1,
        'beforeSystem': false,
      });
      await backend.snapshot();
      final raw = (await call('rawSnapshot') as List).cast<Map>().firstWhere(
        (r) => r['taskId'] == id,
      );
      expect(raw['downloadId'], isA<num>());
    } finally {
      await backend.close();
    }
  });
  testWidgets(
    'interrupted enqueue fails retryably or rebinds the accepted transfer',
    (_) async {
      final backend = AndroidDownloadBackend();
      try {
        final before = newTaskId();
        owned.add(before);
        final request = DownloadRequest(
          taskId: before,
          url: Uri.parse(
            'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16',
          ),
          displayName: 'xdl_probe_$before.mp4',
          headers: const {},
          mediaIndex: 1,
        );
        await call('probeInterruptEnqueue', {
          ...request.toJson(),
          'beforeSystem': true,
        });
        final missing = (await backend.snapshot()).firstWhere(
          (s) => s.taskId == before,
        );
        expect(missing.phase, BackendPhase.failed);
        expect(missing.error, isNotNull);
        final after = newTaskId();
        owned.add(after);
        await call('probeInterruptEnqueue', {
          ...request.withId(after).toJson(),
          'displayName': 'xdl_probe_$after.mp4',
          'beforeSystem': false,
        });
        SavedFile? saved;
        for (var i = 0; i < 30; i++) {
          // A completion receiver must recover the ID even if Flutter never
          // reconciles this accepted transfer after the interrupted enqueue.
          final state = (await call('rawSnapshot') as List)
              .cast<Map>()
              .firstWhere((r) => r['taskId'] == after);
          if (state['savedFile'] != null) {
            saved = SavedFile.fromJson(
              Map<String, dynamic>.from(state['savedFile'] as Map),
            );
            break;
          }
          expect(state['phase'], isNot('failed'));
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(saved?.bytes, 354883);
        final raw = (await call('rawSnapshot') as List).cast<Map>().firstWhere(
          (r) => r['taskId'] == after,
        );
        expect(raw['downloadId'], isA<num>());
        expect(
          (await call('probeInspect', {'taskId': after}) as Map)['publicCount'],
          1,
        );
      } finally {
        await backend.close();
      }
    },
  );

  testWidgets('native publish is idempotent and preserves staging on failure', (
    _,
  ) async {
    final backend = AndroidDownloadBackend();
    final id = await seed(fail: true);
    await expectLater(backend.publish(id), throwsA(isA<AppFailure>()));
    var info = await call('probeInspect', {'taskId': id}) as Map;
    expect(info['stagingExists'], isTrue);
    expect(info['savedNotification'], isFalse);
    await call('probeAllowPublish', {'taskId': id});
    final saved = await backend.publish(id);
    final replay = await AndroidDownloadBackend().publish(id);
    expect(saved.locator, replay.locator);
    await call('probeLoseReceipt', {'taskId': id});
    final recovered = await AndroidDownloadBackend().publish(id);
    expect(recovered.locator, saved.locator);
    info = await call('probeInspect', {'taskId': id}) as Map;
    expect(info['publicCount'], 1);
    expect(info['relativePath'], 'Download/XDownloader/');
    if (info['notificationsEnabled'] == true) {
      expect(info['savedNotification'], isTrue);
    }
    expect(base64Decode(info['data'] as String), mp4);
    await backend.close();
  });
  testWidgets(
    'non-success, empty, and non-video transfers are never exported',
    (_) async {
      for (final id in [
        await seed(status: 404),
        await seed(bytes: []),
        await seed(bytes: utf8.encode('<html>error</html>'), mime: 'text/html'),
      ]) {
        final backend = AndroidDownloadBackend();
        await expectLater(backend.publish(id), throwsA(isA<AppFailure>()));
        final info = await call('probeInspect', {'taskId': id}) as Map;
        expect(info['publicCount'], 0);
        expect(info['stagingExists'], isTrue);
        await backend.close();
      }
    },
  );
  testWidgets('cancel does not delete another task or a published file', (
    _,
  ) async {
    final a = await seed(), b = await seed();
    final backend = AndroidDownloadBackend();
    final saved = await backend.publish(b);
    await backend.cancel(a);
    await backend.cancel(b);
    expect(
      (await call('probeInspect', {'taskId': a}) as Map)['stagingExists'],
      isFalse,
    );
    expect(
      (await call('probeInspect', {'taskId': b}) as Map)['data'],
      isNotEmpty,
    );
    expect((await backend.publish(b)).locator, saved.locator);
    await backend.close();
  });
  testWidgets('system transfer publishes while app is in background', (
    _,
  ) async {
    final id = newTaskId();
    owned.add(id);
    final backend = AndroidDownloadBackend();
    await backend.initialize();
    if (const bool.fromEnvironment('lockScreenTest')) {
      expect(await call('probeDeviceLocked'), isTrue);
    }
    await backend.enqueue(
      DownloadRequest(
        taskId: id,
        url: Uri.parse(
          'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16',
        ),
        displayName: 'xdl_probe_$id.mp4',
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://x.com/',
        },
        mediaIndex: 0,
      ),
    );
    await call('probeBackground');
    Map? receipt;
    for (var i = 0; i < 90; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      // No reconciliation here: proves the native completion job published it.
      final raw = await call('rawSnapshot') as List;
      final record = raw.cast<Map>().firstWhere((r) => r['taskId'] == id);
      if (record['savedFile'] != null) {
        receipt = record['savedFile'] as Map;
        break;
      }
      if (record['phase'] == 'failed') {
        fail('native transfer failed: ${record['error']}');
      }
    }
    expect(
      receipt,
      isNotNull,
      reason: 'background publication must not need foreground reconciliation',
    );
    if (const bool.fromEnvironment('lockScreenTest')) {
      expect(await call('probeDeviceLocked'), isTrue);
      debugPrint('XDL_LOCKSCREEN_PUBLICATION_VERIFIED');
    }
    final info = await call('probeInspect', {'taskId': id}) as Map;
    final data = base64Decode(info['data'] as String);
    expect(
      info['nativeTransferExists'],
      isFalse,
      reason:
          'completed staging transfers must not leave broken Downloads entries',
    );
    expect(data.length, 354883);
    expect(ascii.decode(data.sublist(4, 8)), 'ftyp');
    expect(info['relativePath'], 'Download/XDownloader/');
    expect(
      sha256.convert(data).toString(),
      '3d9e9c81075a71574c4784ee4db6ddcad489d9a7071dd35986c1b58ca2287fa9',
    );
    final restored = AndroidDownloadBackend();
    final snapshot = await restored.snapshot();
    expect(
      snapshot.firstWhere((r) => r.taskId == id).savedFile?.locator,
      receipt!['locator'],
    );
    final duplicateId = newTaskId();
    owned.add(duplicateId);
    await backend.enqueue(
      DownloadRequest(
        taskId: duplicateId,
        url: Uri.parse(
          'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16',
        ),
        displayName: 'xdl_probe_$id.mp4',
        headers: const {'User-Agent': 'Mozilla/5.0'},
        mediaIndex: 0,
      ),
    );
    Map? duplicate;
    for (var i = 0; i < 90; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final raw = await call('rawSnapshot') as List;
      final record = raw.cast<Map>().firstWhere(
        (r) => r['taskId'] == duplicateId,
      );
      if (record['savedFile'] != null) {
        duplicate = record['savedFile'] as Map;
        break;
      }
    }
    expect(duplicate, isNotNull);
    expect(duplicate!['locator'], isNot(receipt['locator']));
    expect(duplicate['displayName'], isNot(receipt['displayName']));
    await call('probeRemoveSavedFile', {'taskId': duplicateId});
    await expectLater(
      backend.open(SavedFile.fromJson(Map<String, dynamic>.from(duplicate))),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          FailureKind.fileMissing,
        ),
      ),
    );
    await call('probeForeground');
    await backend.close();
    await restored.close();
  });
}
