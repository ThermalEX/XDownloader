import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/data/repositories/cover_cache_repository.dart';
import 'package:xdownloader/features/settings/cover_cache_screen.dart';

import '../test/support/app_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'floating favorites privacy password and expiring undo',
    (tester) => withAppFixture(tester, (fixture) async {
      // Probe-only memory repositories and controlled parser; no real media.
      await fixture.settings.edit(
        (s) => s.copyWith(themeMode: AppThemeMode.dark),
      );
      for (var i = 10000; i < 10012; i++) {
        await fixture.favorites.add(
          'https://x.com/demo/status/$i',
          title: '示例视频 $i',
          author: '示例作者',
        );
      }
      Future<void> tap(Finder finder) async {
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await File('${Directory.systemTemp.path}/xdl_probe_$name.png')
            .writeAsBytes(await binding.takeScreenshot(name));
      }

      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.enterText(
        find.byKey(const Key('home_link_input')),
        'https://x.com/demo/status/123456',
      );
      await tap(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '解析'),
      );
      expect(find.text('中文视频'), findsOneWidget);
      await capture('floating_home');
      await tap(find.byKey(const Key('nav_favorites')));
      await capture('floating_favorites');
      await tap(find.byKey(const Key('favorite_actions_10011')));
      await tap(find.text('详情'));
      expect(find.byKey(const Key('favorite_detail_author')), findsOneWidget);
      await capture('favorite_details');
      await tap(find.text('关闭'));
      await tap(find.byKey(const Key('favorite_remove_10011')));
      expect(find.text('撤回'), findsOneWidget);
      await Future<void>.delayed(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('撤回'), findsNothing);
      await tap(find.byKey(const Key('nav_home')));
      await tap(find.byKey(const Key('home_quick_privacy')));
      expect(fixture.settings.value.privacyMode, isTrue);
      expect(find.text('中文视频'), findsNothing);
      expect(find.byKey(const Key('home_quick_privacy')), findsNothing);
      await tap(find.byKey(const Key('nav_settings')));
      await tap(find.text('应用设置'));
      await tap(find.byKey(const Key('privacy_password_setting')));
      await tester.enterText(
        find.byKey(const Key('privacy_new_password')),
        '123456',
      );
      await tester.enterText(
        find.byKey(const Key('privacy_confirm_password')),
        '123456',
      );
      final clock = Stopwatch()..start();
      await tap(find.text('保存'));
      final timeout = Stopwatch()..start();
      while (fixture.settings.value.privacyPasswordHash.isEmpty &&
          timeout.elapsed.inSeconds < 20) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      debugPrint(
        'Probe password creation milliseconds: ${clock.elapsedMilliseconds}',
      );
      expect(fixture.settings.value.privacyPasswordHash, isNotEmpty);
      await tap(find.byKey(const Key('privacy_mode_switch')));
      Future<void> pin(String digits, {bool unlock = false}) async {
        for (final digit in digits.split('')) {
          await tap(find.byKey(Key('privacy_pin_$digit')));
        }
        await tap(find.byKey(const Key('privacy_pin_confirm')));
        // PBKDF2 runs on a real worker isolate; await UI result, not only a
        // frame without scheduled animations.
        final timeout = Stopwatch()..start();
        while ((find.text('正在验证…').evaluate().isNotEmpty ||
                (unlock && fixture.settings.value.privacyMode)) &&
            timeout.elapsed.inSeconds < 20) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      await pin('000000');
      expect(fixture.settings.value.privacyMode, isTrue);
      expect(find.text('密码不正确'), findsOneWidget);
      await capture('privacy_password');
      for (var i = 0; i < 6; i++) {
        await tap(find.byKey(const Key('privacy_pin_delete')));
      }
      await pin('123456', unlock: true);
      expect(fixture.settings.value.privacyMode, isFalse);
      await tap(find.byType(BackButton));
      await tap(find.byKey(const Key('nav_home')));
      expect(find.byKey(const Key('home_quick_privacy')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('home_link_input')))
            .controller!
            .text,
        '',
      );
      final covers = CoverCacheRepository(
        root: Directory('${Directory.systemTemp.path}/xdl_probe_cover_cache'),
        settings: fixture.settings,
      );
      try {
        await covers.initialize();
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => CoverCacheScreen(cache: covers),
              ),
            );
        await tester.pumpAndSettle();
        final rows = find.byType(ListTile);
        final size = tester.getSize(rows.first);
        for (var i = 1; i < 4; i++) {
          expect(tester.getSize(rows.at(i)), size);
        }
        await capture('cache_rows');
        await tap(find.byType(BackButton));
      } finally {
        covers.dispose();
      }
    }),
  );
}
