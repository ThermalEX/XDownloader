import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/platform/platform_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native player controls adjust media volume and restore window brightness and bars',
    (_) async {
      Future<Map> read() async =>
          await callPlatform('readPlaybackControls', {}) as Map;
      final original = await read();
      try {
        await callPlatform('beginPlaybackControls', {});
        await callPlatform('setPlaybackBrightness', {'value': 0.37});
        final changed = await read();
        expect(changed['windowBrightness'], closeTo(0.37, 0.001));
        expect(changed['systemBrightness'], original['systemBrightness']);
        expect(changed['keepScreenOn'], isTrue);
        final target = (original['volume'] as num) > 0.5 ? 0.2 : 0.6;
        final actual = await callPlatform('setPlaybackVolume', {
          'value': target,
        });
        expect((await read())['volume'], actual);
        if (original['volumeFixed'] != true) {
          expect(actual, closeTo(target, 0.1));
        }
        await callPlatform('setPlaybackFullscreen', {'value': true});
        expect((await read())['fullscreen'], isTrue);
        await callPlatform('endPlaybackControls', {});
        final restored = await read();
        expect(restored['windowBrightness'], original['windowBrightness']);
        expect(restored['systemBrightness'], original['systemBrightness']);
        expect(restored['keepScreenOn'], original['keepScreenOn']);
        expect(restored['fullscreen'], isFalse);
      } finally {
        await callPlatform('beginPlaybackControls', {});
        await callPlatform('setPlaybackVolume', {'value': original['volume']});
        await callPlatform('endPlaybackControls', {});
      }
    },
  );
}
