import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/features/favorites/favorites_screen.dart';
import 'package:xdownloader/features/home/home_screen.dart';

import '../support/app_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'fade follows actual input and favorites row midpoints at large text $brightness',
      (tester) => withAppFixture(tester, (fixture) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        await _expectFadeStartsAtRowMidpoint(
          tester,
          'home_content_fade',
          'home_input_row',
        );
        await tester.enterText(
          find.byKey(const Key('home_link_input')),
          'https://x.com/author/status/1234567890123456789',
        );
        await tester.pumpAndSettle();
        await _expectFadeStartsAtRowMidpoint(
          tester,
          'home_content_fade',
          'home_input_row',
        );
        await tester.tap(find.byKey(const Key('nav_favorites')));
        await tester.pumpAndSettle();
        await _expectFadeStartsAtRowMidpoint(
          tester,
          'favorites_content_fade',
          'favorites_action_row',
        );
        expect(tester.takeException(), isNull);
      }),
    );
  }
  testWidgets(
    'home content continues behind the floating composer to navigation',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(
        tester.getBottomLeft(find.byType(HomeScreen)).dy,
        closeTo(navigationTop, .1),
      );
      final fade = find.byKey(const Key('home_content_fade'));
      expect(fade, findsOneWidget);
      expect(tester.widget<ShaderMask>(fade).blendMode, BlendMode.dstIn);

      fixture.clipboard = 'https://x.com/author/status/123456';
      await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(ListView),
      );
      expect(tester.getBottomLeft(list).dy, closeTo(navigationTop, .1));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final before = scroll.position.pixels;
      // The blank space beside the heart must pass vertical drags to content.
      final heartY = tester
          .getCenter(find.byKey(const Key('favorite_current')))
          .dy;
      final gesture = await tester.startGesture(Offset(40, heartY));
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -156));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(before));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('720 × 1280').last).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('home_input_row'))).dy),
      );
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'favorites content continues behind floating actions to navigation',
    (tester) => withAppFixture(tester, (fixture) async {
      for (var i = 10000; i < 10020; i++) {
        await fixture.favorites.add('https://x.com/author/status/$i');
      }
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(
        tester.getBottomLeft(find.byType(FavoritesScreen)).dy,
        closeTo(navigationTop, .1),
      );
      final fade = find.byKey(const Key('favorites_content_fade'));
      expect(fade, findsOneWidget);
      expect(tester.widget<ShaderMask>(fade).blendMode, BlendMode.dstIn);
      final list = find.descendant(
        of: find.byType(FavoritesScreen),
        matching: find.byType(ListView),
      );
      expect(tester.getBottomLeft(list).dy, closeTo(navigationTop, .1));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final visibleRows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('favorite_100'),
      );
      final lastRowBottom = visibleRows
          .evaluate()
          .map(
            (element) => tester.getBottomLeft(find.byWidget(element.widget)).dy,
          )
          .reduce((a, b) => a > b ? a : b);
      expect(
        lastRowBottom,
        lessThan(
          tester.getTopLeft(find.widgetWithText(FilledButton, '添加链接')).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    }),
  );

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

Future<void> _expectFadeStartsAtRowMidpoint(
  WidgetTester tester,
  String fadeKey,
  String rowKey,
) async {
  final fade = find.byKey(Key(fadeKey));
  final mask = tester.widget<ShaderMask>(fade);
  expect(mask.blendMode, BlendMode.dstIn);
  final bounds = Offset.zero & tester.getSize(fade);
  final midpoint =
      tester.getCenter(find.byKey(Key(rowKey))).dy - tester.getTopLeft(fade).dy;
  final alphas = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(bounds, Paint()..shader = mask.shaderCallback(bounds));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      bounds.width.ceil(),
      bounds.height.ceil(),
    );
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(double y) =>
        bytes.getUint8((y.floor() * image.width + 1) * 4 + 3);
    final values = [
      alphaAt(midpoint - 2),
      alphaAt(midpoint + (bounds.height - midpoint) / 2),
      alphaAt(bounds.height - 1),
    ];
    image.dispose();
    picture.dispose();
    return values;
  });
  expect(
    alphas![0],
    255,
    reason: 'content stays clear through the row midpoint',
  );
  expect(
    alphas[1],
    closeTo(127, 8),
    reason: 'only content alpha fades below it',
  );
  expect(alphas[2], lessThan(10));
}
