import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/settings/app_updates_screen.dart';
import 'package:xdownloader/features/settings/settings_screen.dart';

import '../test/support/app_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'theme empty artwork paste resolution cards and guide shortcuts',
    (tester) => withAppFixture(tester, (f) async {
      // Controlled parser and in-memory repositories: no production state,
      // real video transfer or APK installation is part of this UI probe.
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await File('${Directory.systemTemp.path}/xdl_probe_$name.png')
            .writeAsBytes(await binding.takeScreenshot(name));
      }

      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.light));
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.text('还没有解析链接呢~'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await capture('home_empty_light_2100');
      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.dark));
      await capture('home_empty_dark_2100');
      f.clipboard = 'https://x.com/a/status/123456';
      await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      expect(f.parser.calls, [f.clipboard]);
      expect(find.text('中文视频'), findsOneWidget);
      await tester.ensureVisible(find.bySemanticsLabel('下载视频 1，640 × 360'));
      await capture('home_resolutions_2100');
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await capture('favorites_filter_2100');
      await tester.tap(find.byKey(const Key('favorite_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      final settingsScroll = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('关于'),
        180,
        scrollable: settingsScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('usage_guide_entry')));
      await capture('guide_shortcuts_2100');
      final updateLink = find.byKey(const Key('guide_updates'));
      await tester.scrollUntilVisible(
        updateLink,
        220,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(updateLink);
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdatesScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('update_release_page')),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await capture('updates_actions_2100');
      await tester.tap(find.byKey(const Key('update_check')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final homeLink = find.byKey(const Key('guide_tab_0'));
      await tester.scrollUntilVisible(
        homeLink,
        -240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(homeLink);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
    }),
  );
}
