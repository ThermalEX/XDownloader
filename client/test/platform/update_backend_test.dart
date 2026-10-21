import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/platform/android_update_backend.dart';

import '../support/update_fixture.dart';

void main() {
  test('update bridge uses isolated methods and candidate identity', () async {
    final calls = <String>[];
    final update = fixtureUpdate();
    final backend = AndroidUpdateBackend(
      call: (method, args) async {
        calls.add(method);
        if (method == 'updateInstalledApp') {
          return {
            'packageName': 'com.xdl.app',
            'versionName': '2.4.1',
            'versionCode': 14,
            'sdkInt': 37,
            'supportedAbis': ['arm64-v8a'],
          };
        }
        if (method == 'updateSnapshot' || method == 'updateInstall') {
          return {
            'candidateId': update.candidateId,
            'phase': 'ready',
            'bytes': 80,
            'totalBytes': 80,
          };
        }
        if (method == 'updateCancel' || method == 'updateInstall') {
          expect(args['candidateId'], update.candidateId);
        }
        return null;
      },
    );
    expect((await backend.installedApp()).versionCode, 14);
    await backend.enqueue(update, update.assets.first);
    expect((await backend.snapshot()).phase, UpdatePhase.ready);
    expect(
      (await backend.requestInstall(update.candidateId)).phase,
      UpdatePhase.ready,
    );
    await backend.cancel(update.candidateId);
    expect(calls, [
      'updateInstalledApp',
      'updateEnqueue',
      'updateSnapshot',
      'updateInstall',
      'updateCancel',
    ]);
  });
  test(
    'native failures are readable and corrupt platform data rejected',
    () async {
      final backend = AndroidUpdateBackend(
        call: (_, _) async => throw PlatformException(
          code: 'update',
          message: 'signature mismatch',
        ),
      );
      await expectLater(backend.snapshot(), throwsA(isA<AppFailure>()));
      final broken = AndroidUpdateBackend(
        call: (_, _) async => {'phase': 'unknown'},
      );
      await expectLater(broken.snapshot(), throwsA(isA<AppFailure>()));
    },
  );
}
