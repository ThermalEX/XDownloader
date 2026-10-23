import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/settings/naming_settings_screen.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';

import '../support/app_fixture.dart';

Future<void> openFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('favorite_filter')));
  await tester.pumpAndSettle();
}

void main() {
  for (final batch in [false, true]) {
    testWidgets(
      '${batch ? "batch" : "single"} favorite undo notice expires after six seconds',
      (tester) => withAppFixture(tester, (fixture) async {
        await fixture.favorites.add(
          'https://x.com/a/status/123456',
          title: '收藏一',
        );
        if (batch) {
          await fixture.favorites.add(
            'https://x.com/b/status/234567',
            title: '收藏二',
          );
        }
        final original = fixture.favorites.items
            .map((f) => f.toJson())
            .toList();
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_favorites')));
        await tester.pumpAndSettle();

        Future<void> remove() async {
          if (batch) {
            await tester.longPress(find.byKey(const Key('favorite_123456')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('全选'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('favorite_delete_selected')));
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(FilledButton, '删除收藏'));
          } else {
            await tester.tap(find.byKey(const Key('favorite_remove_123456')));
          }
          await tester.pumpAndSettle();
        }

        final message = batch ? '已删除 2 项收藏' : '已取消收藏';
        await remove();
        expect(find.text(message), findsOneWidget);
        expect(find.text('撤回'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('撤回'), findsOneWidget);
        await tester.tap(find.text('撤回'));
        await tester.pumpAndSettle();
        expect(
          fixture.favorites.items.map((f) => f.toJson()).toList(),
          original,
        );

        await remove();
        expect(find.text(message), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('撤回'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text(message), findsNothing);
        expect(find.text('撤回'), findsNothing);
        expect(fixture.favorites.items, isEmpty);
      }),
    );
  }
  testWidgets(
    'one filter icon applies sorting categories and resets to defaults',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add(
        'https://x.com/a/status/123456',
        title: 'Two',
      );
      await fixture.favorites.update('123456', title: 'Two', category: '音乐');
      await fixture.favorites.add(
        'https://x.com/b/status/234567',
        title: 'One',
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('favorite_filter')))
            .isSelected,
        false,
      );
      await openFilter(tester);
      await tester.tap(find.text('名称顺序'));
      await tester.ensureVisible(
        find.byKey(const Key('favorite_filter_category:音乐')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_filter_category:音乐')));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.sort, FavoriteSort.title);
      expect(find.byKey(const Key('favorite_234567')), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('favorite_filter')))
            .isSelected,
        true,
      );
      await openFilter(tester);
      await tester.tap(find.text('默认顺序'));
      await tester.ensureVisible(find.byKey(const Key('favorite_filter_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_filter_all')));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.sort, FavoriteSort.defaultOrder);
      expect(find.byKey(const Key('favorite_234567')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('favorite_filter')))
            .isSelected,
        false,
      );
    }),
  );

  testWidgets(
    'heart removes without opening a link and undo restores original metadata',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add(
        'https://x.com/a/status/123456',
        title: '原收藏',
      );
      await fixture.favorites.update('123456', title: '原收藏', category: '音乐');
      final original = fixture.favorites.items.single.toJson();
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_remove_123456')));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items, isEmpty);
      expect(fixture.parser.calls, isEmpty);
      expect(find.text('已取消收藏'), findsOneWidget);
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items.single.toJson(), original);
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
    }),
  );

  testWidgets(
    'stale heart cannot remove after privacy is enabled',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add(
        'https://x.com/a/status/123456',
        title: '私密名称',
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final action = tester
          .widget<IconButton>(find.byKey(const Key('favorite_remove_123456')))
          .onPressed!;
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      action();
      await tester.pumpAndSettle();
      expect(fixture.favorites.items, hasLength(1));
      expect(find.text('私密名称'), findsNothing);
    }),
  );

  testWidgets(
    'filter draft cancels without changes and narrow large text stays usable',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await fixture.favorites.add('https://x.com/a/status/123456', title: '名称');
      await fixture.favorites.update(
        '123456',
        title: '名称',
        category: '较长的分类名称',
      );
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await fixture.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_favorites')));
        await tester.pumpAndSettle();
        await openFilter(tester);
        await tester.tap(find.text('名称顺序'));
        await tester.scrollUntilVisible(
          find.byKey(const Key('favorite_filter_category:较长的分类名称')),
          150,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(
          find.byKey(const Key('favorite_filter_category:较长的分类名称')),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(fixture.favorites.sort, FavoriteSort.defaultOrder);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('favorite_filter')))
              .isSelected,
          false,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }),
  );

  testWidgets(
    'undo is blocked while private and filtering survives removing its last item',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add('https://x.com/a/status/123456', title: '名称');
      await fixture.favorites.update('123456', title: '名称', category: '音乐');
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await openFilter(tester);
      await tester.ensureVisible(
        find.byKey(const Key('favorite_filter_category:音乐')),
      );
      await tester.tap(find.byKey(const Key('favorite_filter_category:音乐')));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_remove_123456')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite_remove_123456')));
      await tester.pumpAndSettle();
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items, isEmpty);
    }),
  );

  testWidgets(
    'rule summary shows real filename examples and follows saved mode',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.settings.edit(
        (s) => s.copyWith(
          useOriginalFileName: false,
          fileNameTemplate: '{title}_{index}',
        ),
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      expect(find.text('示例视频_1.mp4'), findsOneWidget);
      await tester.tap(find.text('重命名规则'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原始标题'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(NamingSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('示例视频.mp4'), findsOneWidget);
    }),
  );
}
