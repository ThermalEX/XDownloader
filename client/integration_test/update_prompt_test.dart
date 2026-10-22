import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/features/settings/app_updates_screen.dart';
import 'package:xdownloader/features/settings/settings_screen.dart';

import '../test/support/app_fixture.dart';
import '../test/support/update_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'startup prompt suppression manual check and download handoff',
    (tester) => withAppFixture(tester, (f) async {
      // Isolated in-memory repositories and fake update backend: no installation
      // or download of an APK on the device during this interaction test.
      f.releaseClient.respond = (_) async => ReleaseCheck(
        candidate: fixtureUpdate(),
        scopeComplete: true,
        skippedReleases: 0,
        validReleases: 1,
      );
      await f.updates.setAutoCheck(true);
      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.light));
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await File(
        '${Directory.systemTemp.path}/xdl_probe_update_prompt_light.png',
      ).writeAsBytes(await binding.takeScreenshot('update-prompt-light'));
      await tester.tap(find.text('不再提醒'));
      await tester.pumpAndSettle();
      expect(f.updates.preferences.showUpdatePrompt, false);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(f.releaseClient.checks, 2);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      expect(find.text('新版说明'), findsNothing);
      final check = find.widgetWithText(FilledButton, '检查更新');
      await tester.scrollUntilVisible(
        check,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['enqueue']);
      expect(find.text('正在下载安装包'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('正在下载安装包'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.dark));
      await f.updates.setShowUpdatePrompt(true);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await File(
        '${Directory.systemTemp.path}/xdl_probe_update_prompt_dark.png',
      ).writeAsBytes(await binding.takeScreenshot('update-prompt-dark'));
      expect(f.updateBackend.calls, ['enqueue']);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('关于'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      final guide = find.byKey(const Key('usage_guide_entry'));
      await tester.scrollUntilVisible(
        guide,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(guide);
      await tester.pumpAndSettle();
      expect(find.text('快速下载'), findsOneWidget);
      await File('${Directory.systemTemp.path}/xdl_probe_guide_dark.png')
          .writeAsBytes(await binding.takeScreenshot('guide-dark'));
      await tester.scrollUntilVisible(
        find.text('应用更新'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('不再提醒'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('关于'), findsOneWidget);
    }),
  );
}
