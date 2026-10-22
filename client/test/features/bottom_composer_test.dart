import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';

import '../support/app_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'page swipe keeps empty states at fixed vertical positions $brightness',
      (tester) => withAppFixture(tester, (fixture) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        final art = find.byKey(const Key('home_empty_art'));
        final startY = tester.getCenter(art).dy;
        final pager = find.byType(PageView);
        final size = tester.getSize(pager);
        final origin = tester.getTopLeft(pager);
        final gesture = await tester.startGesture(
          origin + Offset(size.width * .85, size.height * .3),
        );
        await gesture.moveBy(Offset(-size.width * .35, 0));
        await tester.pump();
        final downloadsY = tester.getCenter(find.text('还没有下载记录')).dy;
        expect(tester.getCenter(art).dy, closeTo(startY, .1));
        await gesture.moveBy(Offset(-size.width * .3, 0));
        await tester.pump();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(tester.getCenter(art).dy, closeTo(startY, .1));
        expect(
          tester.getCenter(find.text('还没有下载记录')).dy,
          closeTo(downloadsY, .1),
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.text('还没有下载记录')).dy,
          closeTo(downloadsY, .1),
        );
        expect(tester.takeException(), isNull);
      }),
    );
  }
  testWidgets(
    'bottom composer pastes clears parses and reflects saved hearts',
    (tester) => withAppFixture(tester, (fixture) async {
      fixture.clipboard = 'https://x.com/author/status/123456';
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存喜欢的视频'), findsNothing);
      final field = find.byType(TextField).first;
      final nav = find.byType(NavigationBar);
      expect(
        tester.getBottomLeft(field).dy,
        greaterThan(tester.getTopLeft(nav).dy - 120),
      );
      await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('清空'), findsOneWidget);
      expect(find.text('中文视频'), findsOneWidget);
      expect(
        find.byKey(const Key('favorite_current')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.byKey(const Key('favorite_current')));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items.single.postId, '123456');
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_current')),
          matching: find.byIcon(Icons.favorite),
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(SnackBar), const Offset(0, 160));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('从剪贴板粘贴'), findsOneWidget);
      expect(find.text('中文视频'), findsNothing);
    }),
  );

  testWidgets(
    'favorites actions stay equal and below the scrollable list',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, '添加链接');
      final paste = find.widgetWithText(FilledButton, '从剪贴板添加');
      expect(paste, findsOneWidget);
      expect(tester.getSize(add), tester.getSize(paste));
      expect(
        tester.getTopLeft(add).dy,
        greaterThan(tester.getBottomLeft(find.text('还没有收藏')).dy),
      );
      fixture.clipboard = 'https://x.com/author/status/123456';
      await tester.tap(paste);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
    }),
  );

  testWidgets(
    'composer stays above keyboard on small and landscape screens',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final layout in [
        (const Size(320, 640), 260.0),
        (const Size(760, 375), 160.0),
      ]) {
        tester.view.physicalSize = layout.$1;
        tester.view.viewInsets = FakeViewPadding(bottom: layout.$2);
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const Key('home_link_input'));
        await tester.enterText(input, 'https://x.com/author/status/123456');
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(input).dy,
          lessThanOrEqualTo(layout.$1.height - layout.$2),
        );
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(fixture.parser.calls.last, 'https://x.com/author/status/123456');
        expect(tester.takeException(), isNull);
      }
    }),
  );
}
