import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/favorites/favorite_category_bar.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'category overflow fades, scrolls independently and stays usable at 320dp with large text',
    (tester) => withAppFixture(tester, (f) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (var i = 0; i < 6; i++) {
        await f.favorites.addCategory('分类 $i');
      }
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await f.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_favorites')));
        await tester.pumpAndSettle();
        final bar = find.byType(FavoriteCategoryBar);
        final scroll = find.descendant(
          of: bar,
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scroll).position;
        expect(position.extentAfter, greaterThan(0));
        await tester.drag(bar, const Offset(-900, 0));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('favorite_category:分类 5')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('favorite_category:分类 5')));
        await tester.pumpAndSettle();
        expect(find.text('所选分类还没有收藏'), findsOneWidget);
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(const Key('favorite_category:分类 5')),
              )
              .selected,
          true,
        );
        expect(
          tester.getSize(find.byKey(const Key('favorite_add_category'))).width,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }),
  );
  testWidgets(
    'category tabs switch views and filter applies multiple categories as a union',
    (tester) => withAppFixture(tester, (f) async {
      for (final (id, group) in [
        ('123456', 'Music'),
        ('234567', 'Work'),
        ('345678', ''),
      ]) {
        await f.favorites.add('https://x.com/a/status/$id', title: id);
        await f.favorites.update(id, title: id, category: group);
      }
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_category:Music')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_234567')), findsNothing);
      await tester.tap(find.byKey(const Key('favorite_filter')));
      await tester.pumpAndSettle();
      final work = find.byKey(const Key('favorite_filter_category:Work'));
      await tester.ensureVisible(work);
      await tester.pumpAndSettle();
      await tester.tap(work);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
      expect(find.byKey(const Key('favorite_234567')), findsOneWidget);
      expect(find.byKey(const Key('favorite_345678')), findsNothing);
      await tester.tap(find.byKey(const Key('favorite_category_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_345678')), findsOneWidget);
    }),
  );
  testWidgets(
    'plus creates a durable empty category and privacy hides an open category editor',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final plus = find.byKey(const Key('favorite_add_category'));
      final filter = find.byKey(const Key('favorite_filter'));
      expect(tester.getCenter(plus).dx, lessThan(tester.getCenter(filter).dx));
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '旅行',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      expect(f.favorites.categories, ['旅行']);
      expect(find.byKey(const Key('favorite_category:旅行')), findsOneWidget);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '秘密',
      );
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_category_name')), findsNothing);
      expect(find.text('秘密'), findsNothing);
      expect(find.text('添加'), findsNothing);
      expect(find.byKey(const Key('favorite_category:旅行')), findsNothing);
    }),
  );
}
