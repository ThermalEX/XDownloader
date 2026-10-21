import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/platform/platform_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'granted install permission restores ready status after consent return',
    (tester) async {
      expect(await callPlatform('probeCanInstallUpdates', {}), true);
      final raw = await callPlatform('probeLoadUpdateFixtures', {}) as String;
      final fixture = Map<String, Object?>.from(
        (jsonDecode(raw) as List).first as Map,
      );
      try {
        final result = await callPlatform('probeStageReadyUpdate', {
          ...fixture,
          'permissionRequired': true,
        }) as Map;
        expect(result['phase'], 'ready');
      } finally {
        await callPlatform('probeClearReadyUpdate', {});
      }
    },
    skip: !const bool.fromEnvironment('expectUpdateInstallGranted'),
  );
  testWidgets(
    'native APK validation trusts installed signer and rejects altered packages',
    (tester) async {
      final raw = await callPlatform('probeLoadUpdateFixtures', {}) as String;
      expect(
        raw,
        isNotEmpty,
        reason:
            'Build fixtures with client/tool/build_update_probe_fixtures.py',
      );
      final fixtures = jsonDecode(raw) as List;
      for (final value in fixtures) {
        final fixture = Map<String, Object?>.from(value as Map);
        if (fixture['success'] == true) {
          final result =
              await callPlatform('probeVerifyUpdate', fixture) as Map;
          expect(result['verified'], true);
          expect(
            result['uri'],
            startsWith('content://com.xdl.app.probe.files/app_updates/'),
          );
          expect(result['mimeType'], 'application/vnd.android.package-archive');
          expect(result['grantRead'], true);
        } else {
          final reason = switch (fixture['label']) {
            'hash' => '校验失败',
            'bytes' || 'replaced-after-verify' => '大小不符',
            'package' => '本应用',
            'signer' => '签名',
            'sdk' => '不兼容',
            _ => '版本',
          };
          await expectLater(
            callPlatform('probeVerifyUpdate', fixture),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.message,
                'rejection reason',
                contains(reason),
              ),
            ),
            reason: fixture['label'] as String,
          );
        }
      }
    },
  );
  testWidgets(
    'native interrupted enqueue recovers its ID and cancel preserves another transfer',
    (tester) async {
      final result = await callPlatform('probeUpdateRecovery', {}) as Map;
      expect(result['recovered'], true);
      expect(result['videoPreserved'], true);
      expect(result['updateRemoved'], true);
    },
  );
  testWidgets('ready verified package survives system task pruning', (
    tester,
  ) async {
    final raw = await callPlatform('probeLoadUpdateFixtures', {}) as String;
    final fixture = Map<String, Object?>.from(
      (jsonDecode(raw) as List).first as Map,
    );
    try {
      final result =
          await callPlatform('probeStageReadyUpdate', fixture) as Map;
      expect(result['phase'], 'ready');
    } finally {
      await callPlatform('probeClearReadyUpdate', {});
    }
  });
  testWidgets(
    'unknown-source consent is requested and retry state survives returning',
    (tester) async {
      expect(
        await callPlatform('probeCanInstallUpdates', {}),
        false,
        reason: 'Run this probe with its REQUEST_INSTALL_PACKAGES app-op denied; never alter production permissions',
      );
      final raw = await callPlatform('probeLoadUpdateFixtures', {}) as String;
      final fixture = Map<String, Object?>.from(
        (jsonDecode(raw) as List).first as Map,
      );
      try {
        await callPlatform('probeStageReadyUpdate', fixture);
        final result = await callPlatform('updateInstall', {
          'candidateId': 'probe-stage',
        }) as Map;
        expect(result['phase'], 'permissionRequired');
        await callPlatform('probeReturnToApp', {});
        final resumed = await callPlatform('updateSnapshot', {}) as Map;
        expect(resumed['phase'], 'permissionRequired');
      } finally {
        await callPlatform('probeReturnToApp', {});
        await callPlatform('probeClearReadyUpdate', {});
      }
    },
  );
}
