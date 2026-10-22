import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/app_settings.dart';

import '../support/app_fixture.dart';

Future<void> seedDownloaded(AppFixture f) async {
  for (final id in ['a', 'b', 'old']) {
    await f.downloads.start(
      DownloadRequest(
        taskId: id,
        url: Uri.parse('https://video.twimg.com/$id.mp4'),
        displayName: '$id.mp4',
        headers: const {},
        mediaIndex: 1,
        postUrl: id == 'old'
            ? null
            : Uri.parse('https://twitter.com/demo/status/123456?s=20'),
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
}

void main() {
  testWidgets(
    'selection actions and status fit a short narrow screen in both themes',
    (tester) => withAppFixture(tester, (f) async {
      await seedDownloaded(f);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await f.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_downloads')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('download_a')),
          150,
          scrollable: find.descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(const Key('download_a')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getCenter(find.text('删除文件')).dy,
          closeTo(tester.getCenter(find.text('移除记录')).dy, 1),
        );
        expect(
          tester.getTopLeft(find.text('全选')).dy,
          greaterThan(tester.getBottomLeft(find.text('移除记录')).dy),
        );
        await tester.tap(find.byTooltip('退出多选'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }),
  );
  testWidgets(
    'long-press batch adds canonical source once without touching files or history',
    (tester) => withAppFixture(tester, (f) async {
      await seedDownloaded(f);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_a')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('已选 1 项')).dy,
        greaterThan(tester.getBottomLeft(find.text('移除记录')).dy),
      );
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('downloads_favorite_selected')));
      await tester.pumpAndSettle();
      expect(
        f.favorites.items.single.url.toString(),
        'https://x.com/demo/status/123456',
      );
      expect(f.downloads.records, hasLength(3));
      expect(f.downloads.history, hasLength(3));
      expect(f.backend.saved, hasLength(3));
      expect(find.textContaining('无原链接'), findsOneWidget);
      await f.favorites.update('123456', title: '自定义名称', category: '音乐');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('download_a')),
          matching: find.byTooltip('下载操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加收藏'));
      await tester.pumpAndSettle();
      expect(f.favorites.items.single.title, '自定义名称');
      expect(f.favorites.items.single.category, '音乐');
    }),
  );
  testWidgets(
    'privacy blocks a stale download-to-favorites action',
    (tester) => withAppFixture(tester, (f) async {
      await seedDownloaded(f);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_a')));
      await tester.pumpAndSettle();
      final action = tester
          .widget<FilledButton>(
            find.byKey(const Key('downloads_favorite_selected')),
          )
          .onPressed!;
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      action();
      await tester.pumpAndSettle();
      expect(f.favorites.items, isEmpty);
    }),
  );
}
