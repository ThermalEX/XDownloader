import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'swipes and navigation taps stay synchronized and preserve page state',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '保留手动输入');
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await tester.tap(find.byKey(const Key('nav_home')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('保留手动输入'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      fixture.shareEvents.add('https://x.com/author/status/123456');
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('中文视频'), findsOneWidget);
    }),
  );
  testWidgets(
    'settings home contains categories and appearance opens a second-level page',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme_mode')), findsNothing);
      expect(find.text('动态取色'), findsNothing);
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme_mode')), findsOneWidget);
      expect(find.text('动态取色'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme_mode')), findsNothing);
      expect(find.text('规则设置'), findsOneWidget);
      expect(find.text('应用设置'), findsOneWidget);
      expect(find.text('下载与存储'), findsOneWidget);
    }),
  );
}
