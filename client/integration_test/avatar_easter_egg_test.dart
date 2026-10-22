import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/features/settings/about_screen.dart';
import 'package:xdownloader/features/settings/avatar_easter_egg.dart';

import '../test/support/app_fixture.dart';
import '../test/support/particle_canvas.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'comic puffs anger marks and Japanese heart accents render',
    (tester) => withAppFixture(tester, (f) async {
      // Separate visual harness keeps seeded art checks deterministic.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            appBar: AppBar(title: const Text('彩蛋效果验收')),
            body: Center(
              child: AvatarEasterEgg(
                settings: f.settings,
                random: math.Random(47),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      var sawVein = false, sawWord = false, sawLines = false;
      for (final hearts in [false, true]) {
        for (var i = 0; i < 64; i++) {
          await f.settings.edit((s) => s.copyWith(playfulAvatar: hearts));
          await tester.tap(find.byKey(const Key('about_avatar_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 220));
          if (f.settings.value.playfulAvatar != hearts) {
            await tester.pumpAndSettle();
            continue;
          }
          final sample = snapshotParticles(tester);
          String? name;
          if (!hearts && !sawVein && sample.colors.length > 1) {
            sawVein = true;
            name = 'comic_steam_vein';
          } else if (hearts && !sawWord && sample.paragraphs > 0) {
            sawWord = true;
            name = 'comic_heart_japanese';
          } else if (hearts && !sawLines && sample.tremblingMarks > 0) {
            sawLines = true;
            name = 'comic_heart_lines';
          }
          if (name != null) {
            await File('${Directory.systemTemp.path}/xdl_probe_$name.png')
                .writeAsBytes(await binding.takeScreenshot(name));
          }
          await tester.pumpAndSettle();
          if ((!hearts && sawVein) || (hearts && sawWord && sawLines)) break;
        }
      }
      expect(sawVein && sawWord && sawLines, true);
      expect(tester.takeException(), isNull);
    }),
  );
  testWidgets(
    'six-tap avatar cycle persists and updates Home',
    (tester) => withAppFixture(tester, (f) async {
      Future<void> capture(String name) async {
        await File('${Directory.systemTemp.path}/xdl_probe_$name.png')
            .writeAsBytes(await binding.takeScreenshot(name));
      }

      String asset(String key) =>
          (tester.widget<Image>(find.byKey(Key(key))).image as ResizeImage)
              .imageProvider
              .toString();

      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      void openAbout() => navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AboutScreen(dependencies: f.dependencies),
        ),
      );
      openAbout();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('avatar_anger_burst')), findsWidgets);
      await capture('avatar_anger_small');
      await tester.pump(const Duration(milliseconds: 240));
      await capture('avatar_anger');
      for (var i = 1; i < 6; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byKey(const Key('avatar_heart_burst')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(asset('about_avatar_image'), contains('playful_avatar.png'));
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('avatar_heart_burst')), findsWidgets);
      await capture('avatar_hearts_small');
      await tester.pump(const Duration(milliseconds: 240));
      await capture('avatar_hearts');
      final restored = SettingsRepository(f.store);
      await restored.initialize();
      expect(restored.value.playfulAvatar, true);
      restored.dispose();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(asset('home_empty_art'), contains('playful_avatar.png'));
      await capture('avatar_home_playful');
      openAbout();
      await tester.pumpAndSettle();
      // Leaving About discarded the first heart tap; six fresh taps are needed.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(f.settings.value.playfulAvatar, true);
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pumpAndSettle();
      expect(f.settings.value.playfulAvatar, false);
      expect(asset('about_avatar_image'), contains('app_icon.png'));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(asset('home_empty_art'), contains('app_icon.png'));
      expect(tester.takeException(), isNull);
    }),
  );
}
