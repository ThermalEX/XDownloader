import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/home/home_controller.dart';
import 'package:xdownloader/features/settings/app_updates_screen.dart';
import 'package:xdownloader/features/settings/about_screen.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'empty and parsed home stay usable in both themes at 320dp doubled text',
    (tester) => withAppFixture(tester, (f) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await f.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
        await tester.pumpAndSettle();
        expect(find.text('还没有解析链接呢~'), findsOneWidget);
        f.clipboard = 'https://x.com/a/status/123456';
        await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
        await tester.pumpAndSettle();
        final row = find.bySemanticsLabel('下载视频 1，640 × 360');
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(f.downloads.records.last.request.width, 640);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }),
  );
  testWidgets(
    'guide tab shortcut returns to the existing shell instead of nesting a second page',
    (tester) => withAppFixture(tester, (f) async {
      await f.favorites.add('https://x.com/a/status/123456', title: '保留收藏');
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('关于'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('usage_guide_entry')));
      await tester.pumpAndSettle();
      final shortcut = find.byKey(const Key('guide_tab_2'));
      await tester.scrollUntilVisible(
        shortcut,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.text('保留收藏'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    }),
  );
  testWidgets(
    'empty home is themed and explicit paste parses exactly once',
    (tester) => withAppFixture(tester, (f) async {
      f.clipboard = '分享 https://x.com/a/status/123456';
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.text('还没有解析链接呢~'), findsOneWidget);
      expect(find.byKey(const Key('home_empty_art')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      expect(f.parser.calls, [f.clipboard]);
      expect(find.text('中文视频'), findsOneWidget);
      expect(find.text('还没有解析链接呢~'), findsNothing);
      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      expect(find.text('还没有解析链接呢~'), findsOneWidget);
    }),
  );
  test('pending explicit paste is ignored after leaving home and invalid clipboard is not parsed', () async {
    final f = AppFixture();
    await f.initialize();
    final home = HomeController(f.dependencies);
    try {
      f.clipboard = 'https://x.com/a/status/123456';
      final pending = home.paste();
      home.setVisible(false);
      await pending;
      expect(f.parser.calls, isEmpty);
      home.setVisible(true);
      f.clipboard = '普通文字';
      await expectLater(home.paste(), throwsA(anything));
      expect(f.parser.calls, isEmpty);
    } finally {
      home.dispose();
      await f.close();
    }
  });
  testWidgets(
    'favorite filter keeps filled funnel appearance even with default filters',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final finder = find.byKey(const Key('favorite_filter'));
      final button = tester.widget<IconButton>(finder);
      expect(
        find.descendant(
          of: finder,
          matching: find.byIcon(Icons.filter_list_alt),
        ),
        findsOneWidget,
      );
      expect(
        button.style?.backgroundColor?.resolve({}),
        isNot(Colors.transparent),
      );
      expect(button.isSelected, false);
    }),
  );
  testWidgets(
    'update actions share a card and equal buttons while browser remains functional',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      final check = find.byKey(const Key('update_check'));
      final page = find.byKey(const Key('update_release_page'));
      await tester.scrollUntilVisible(
        page,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(check), tester.getSize(page));
      expect(
        find.ancestor(of: check, matching: find.byType(Card)).evaluate().single,
        find.ancestor(of: page, matching: find.byType(Card)).evaluate().single,
      );
      await tester.tap(page);
      await tester.pumpAndSettle();
      expect(f.updateBackend.pages.single.host, 'github.com');
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }),
  );
  testWidgets(
    'guide links open their settings and return to the guide',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('usage_guide_entry')));
      await tester.pumpAndSettle();
      for (final (key, title) in [
        ('guide_sources', '下载源'),
        ('guide_naming', '重命名规则'),
        ('guide_application', '应用设置'),
        ('guide_updates', '应用更新'),
      ]) {
        final link = find.byKey(Key(key));
        await tester.scrollUntilVisible(
          link,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, title), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, '使用说明'), findsOneWidget);
      }
    }),
  );
}
