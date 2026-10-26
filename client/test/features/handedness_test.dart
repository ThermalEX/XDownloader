import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'both hand modes fit narrow screens with large text in both themes',
    (tester) => withAppFixture(tester, (f) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await f.favorites.add('https://x.com/a/status/123456', title: '收藏示例');
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      for (final theme in [AppThemeMode.light, AppThemeMode.dark]) {
        for (final hand in Handedness.values) {
          await f.settings.edit(
            (s) => s.copyWith(themeMode: theme, handedness: hand),
          );
          await tester.pumpAndSettle();
          for (final tab in ['home', 'downloads', 'favorites', 'settings']) {
            await tester.tap(find.byKey(Key('nav_$tab')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$theme $hand $tab');
          }
        }
      }
    }),
  );
  testWidgets(
    'left-hand list menus, filter and history move without changing content',
    (tester) => withAppFixture(tester, (f) async {
      await f.settings.edit((s) => s.copyWith(handedness: Handedness.left));
      await f.favorites.add('https://x.com/a/status/123456', title: '收藏示例');
      await f.downloads.start(
        DownloadRequest(
          taskId: 'hand',
          url: Uri.parse('https://video.twimg.com/hand.mp4'),
          displayName: '测试文件.mp4',
          headers: const {},
          mediaIndex: 1,
          postUrl: Uri.parse('https://x.com/a/status/123456'),
        ),
      );
      f.backend.emit(
        BackendTaskSnapshot(
          taskId: 'hand',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await f.downloads.reconcile();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final menu = find.byKey(const Key('favorite_actions_123456'));
      final heart = find.byKey(const Key('favorite_remove_123456'));
      expect(
        tester.getCenter(menu).dx,
        lessThan(tester.getCenter(find.text('收藏示例')).dx),
      );
      expect(
        tester.getRect(heart).right,
        lessThanOrEqualTo(tester.getRect(menu).left),
      );
      expect(
        tester.getCenter(find.byKey(const Key('favorite_filter'))).dx,
        lessThan(400),
      );
      await tester.tap(find.byKey(const Key('favorite_filter')));
      await tester.pumpAndSettle();
      final allCategories = find.byKey(const Key('favorite_filter_all'));
      final checkbox = find.descendant(
        of: allCategories,
        matching: find.byType(Checkbox),
      );
      final allLabel = find.descendant(
        of: allCategories,
        matching: find.text('全部'),
      );
      expect(
        tester.getCenter(checkbox).dx,
        lessThan(tester.getCenter(allLabel).dx),
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('favorites_search')), '收藏');
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byTooltip('清空搜索')).dx, lessThan(400));
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byTooltip('下载操作')).dx,
        lessThan(tester.getCenter(find.text('测试文件.mp4')).dx),
      );
      expect(
        tester.getCenter(find.byKey(const Key('download_history'))).dx,
        lessThan(400),
      );
      await tester.longPress(find.text('测试文件.mp4'));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('全选')).dx, lessThan(400));
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_history')));
      await tester.pumpAndSettle();
      final historyMenu = find.byKey(const Key('history_actions_hand'));
      expect(
        tester.getCenter(historyMenu).dx,
        lessThan(tester.getCenter(find.text('测试文件.mp4')).dx),
      );
      await f.settings.edit((s) => s.copyWith(handedness: Handedness.right));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(historyMenu).dx,
        greaterThan(tester.getCenter(find.text('测试文件.mp4')).dx),
      );
      expect(
        Directionality.of(tester.element(find.text('测试文件.mp4'))),
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    }),
  );
  test(
    'hand preference survives snapshots and unrelated settings edits',
    () async {
      final store = MemorySnapshotStore();
      await store.write('settings', {'handedness': 'left'});
      final settings = SettingsRepository(store);
      await settings.initialize();
      await settings.edit((s) => s.copyWith(autoClipboard: false));
      expect((await store.read('settings'))['handedness'], 'left');
      expect(AppSettings.fromJson({}).toJson()['handedness'], 'right');
      expect(
        AppSettings.fromJson({'handedness': 'unknown'}).toJson()['handedness'],
        'right',
      );
      settings.dispose();
    },
  );

  testWidgets(
    'left mode moves home controls without reversing text or settings',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final parse = find.bySemanticsLabel('解析链接');
      final input = find.byKey(const Key('home_link_input'));
      expect(
        tester.getCenter(parse).dx,
        greaterThan(tester.getCenter(input).dx),
      );
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      final privacy = find.byKey(const Key('privacy_mode_switch'));
      final before = tester.getRect(privacy);
      expect(find.text('左手'), findsOneWidget);
      await tester.ensureVisible(find.text('左手'));
      await tester.tap(find.text('左手'));
      await tester.pumpAndSettle();
      expect((await f.store.read('settings'))['handedness'], 'left');
      expect(tester.getRect(privacy).left, before.left);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_home')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(parse).dx, lessThan(tester.getCenter(input).dx));
      expect(
        tester.getCenter(find.byKey(const Key('favorite_current'))).dx,
        lessThan(tester.getCenter(input).dx),
      );
      expect(
        tester.getCenter(find.byKey(const Key('home_quick_privacy'))).dx,
        lessThan(tester.getCenter(find.text('XDownloader')).dx),
      );
      expect(Directionality.of(tester.element(input)), TextDirection.ltr);
      // Native prefix slots reserve space for the unfocused label as well as input.
      expect(
        tester.getRect(find.byTooltip('粘贴')).right,
        lessThanOrEqualTo(tester.getRect(find.text('视频链接')).left),
      );
      await tester.enterText(input, 'https://x.com/author/status/123456');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'https://x.com/author/status/123456',
      );
      expect(tester.takeException(), isNull);
    }),
  );
}
