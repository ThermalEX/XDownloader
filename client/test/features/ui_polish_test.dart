import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/features/home/home_screen.dart';
import 'package:xdownloader/features/settings/settings_group.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'closing keyboard or system back ends expanded link editing',
    (tester) => withAppFixture(tester, (fixture) async {
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('home_link_input'));
      await tester.enterText(
        input,
        'https://x.com/long_author/status/1234567890123456789',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).maxLines, 1);
      await tester.enterText(input, 'https://x.com/demo/status/123456');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).maxLines, 1);
    }),
  );
  testWidgets(
    'link collapses after editing and heart reserves footer space',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('home_link_input'));
      expect(tester.widget<TextField>(input).maxLines, 1);
      await tester.enterText(
        input,
        'https://x.com/long_author/status/1234567890123456789',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).maxLines, 3);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).maxLines, 1);
      final content = find.byType(HomeScreen);
      final heart = find.byKey(const Key('favorite_current'));
      expect(
        tester.getTopLeft(heart).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(content).dy),
      );
      expect(
        tester.getBottomLeft(heart).dy,
        lessThan(tester.getTopLeft(input).dy),
      );
    }),
  );

  testWidgets(
    'settings root groups rows without panels and detail keeps panels',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPanel), findsNothing);
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPanel), findsWidgets);
    }),
  );

  testWidgets(
    'navigation tap chooses target without selecting intermediate pages',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pump(const Duration(milliseconds: 80));
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 3);
      expect(
        nav.overlayColor?.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      await tester.pumpAndSettle();
    }),
  );
}
