import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/features/favorites/favorite_category_bar.dart';

import '../test/support/app_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final categoryCount in [0, 8]) {
    testWidgets(
      'category bar stays interactive before page settles ($categoryCount)',
      (tester) => withAppFixture(tester, (f) async {
        for (var i = 0; i < categoryCount; i++) {
          await f.favorites.addCategory('分类 $i');
        }
        await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.dark));
        await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_downloads')));
        await tester.pumpAndSettle();
        final pager = find.byType(PageView);
        final pages = tester.widget<PageView>(pager).controller!;
        unawaited(
          pages.animateToPage(
            2,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(pages.page, greaterThan(1.5));
        expect(pages.page, lessThan(2));
        final bar = find.byType(FavoriteCategoryBar);
        final visible = tester.getRect(bar).intersect(tester.getRect(pager));
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: bar, matching: find.byType(Scrollable)),
            )
            .position;
        final gesture = await tester.startGesture(visible.center);
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(pages.page, 2);
        if (categoryCount > 0) expect(position.pixels, greaterThan(0));
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await File(
          '${Directory.systemTemp.path}/xdl_probe_category_gesture_$categoryCount.png',
        ).writeAsBytes(
          await binding.takeScreenshot('category-gesture-$categoryCount'),
        );
        await tester.drag(pager, Offset(-tester.getSize(pager).width * .8, 0));
        await tester.pumpAndSettle();
        expect(pages.page, 3);
        expect(tester.takeException(), isNull);
      }),
    );
  }
  testWidgets(
    'download favorite and category navigation on isolated probe UI',
    (tester) => withAppFixture(tester, (f) async {
      // No real downloads, saved media or production state are touched.
      for (final id in ['123456', '234567']) {
        await f.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '示例视频 $id.mp4',
            headers: const {},
            mediaIndex: 1,
            postUrl: Uri.parse('https://twitter.com/demo/status/$id?s=20'),
          ),
        );
        f.backend.emit(
          BackendTaskSnapshot(
            taskId: id,
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
      }
      await f.downloads.reconcile();
      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.dark));
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_123456')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('已选 2 项')).dy,
        greaterThan(tester.getBottomLeft(find.text('移除记录')).dy),
      );
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await File(
        '${Directory.systemTemp.path}/xdl_probe_download_categories_dark.png',
      ).writeAsBytes(await binding.takeScreenshot('download-selection-dark'));
      await tester.tap(find.byKey(const Key('downloads_favorite_selected')));
      await tester.pumpAndSettle();
      expect(f.favorites.items, hasLength(2));
      expect(f.downloads.records, hasLength(2));
      expect(f.downloads.history, hasLength(2));
      await f.favorites.update('123456', title: '示例音乐', category: '音乐');
      await f.favorites.update('234567', title: '示例旅行', category: '旅行');
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_add_category')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '稍后观看',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      expect(f.favorites.categories, contains('稍后观看'));
      await tester.tap(find.byKey(const Key('favorite_category:音乐')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_234567')), findsNothing);
      await tester.tap(find.byKey(const Key('favorite_filter')));
      await tester.pumpAndSettle();
      final travel = find.byKey(const Key('favorite_filter_category:旅行'));
      await tester.ensureVisible(travel);
      await tester.pumpAndSettle();
      await tester.tap(travel);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
      expect(find.byKey(const Key('favorite_234567')), findsOneWidget);
      await File(
        '${Directory.systemTemp.path}/xdl_probe_favorite_categories_dark.png',
      ).writeAsBytes(await binding.takeScreenshot('favorite-categories-dark'));
      await f.settings.edit((s) => s.copyWith(themeMode: AppThemeMode.light));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(FavoriteCategoryBar),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_category:稍后观看')));
      await tester.pumpAndSettle();
      expect(find.text('所选分类还没有收藏'), findsOneWidget);
      await File(
        '${Directory.systemTemp.path}/xdl_probe_favorite_categories_light.png',
      ).writeAsBytes(await binding.takeScreenshot('favorite-categories-light'));
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      expect(find.byType(FavoriteCategoryBar), findsNothing);
      expect(find.text('示例音乐'), findsNothing);
      expect(tester.takeException(), isNull);
    }),
  );
}
