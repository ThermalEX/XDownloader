import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/features/settings/about_screen.dart';

import '../support/app_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'about opens readable guide at 320dp doubled text ${brightness.name}',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AboutScreen(dependencies: f.dependencies),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const Key('usage_guide_entry'));
        await tester.scrollUntilVisible(
          entry,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('使用说明'), findsOneWidget);
        expect(find.text('快速下载'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('应用更新'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('不再提醒'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('关于'), findsOneWidget);
      }),
    );
  }
}
