import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/features/settings/about_screen.dart';

import '../support/app_fixture.dart';

Future<void> showAbout(
  WidgetTester tester,
  AppFixture fixture, {
  required Brightness brightness,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AboutScreen(dependencies: fixture.dependencies),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Finder> revealRow(WidgetTester tester, String title) async {
  final row = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  await tester.scrollUntilVisible(
    row,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return row;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'about rows stay equal and fade single lines at 320dp '
        '${brightness.name} ${textScale}x',
        (tester) => withAppFixture(tester, (fixture) async {
          await showAbout(
            tester,
            fixture,
            brightness: brightness,
            textScale: textScale,
          );
          double? rowHeight;
          for (final title in ['使用说明', '更新日志', '作者', '技术栈', 'GitHub 源码仓库']) {
            final row = await revealRow(tester, title);
            final height = tester.getSize(row).height;
            rowHeight ??= height;
            expect(height, rowHeight, reason: title);
            expect(height, greaterThanOrEqualTo(48));
            final tile = tester.widget<ListTile>(row);
            for (final text in [tile.title, tile.subtitle].whereType<Text>()) {
              expect(text.maxLines, 1, reason: '$title: ${text.data}');
              expect(text.softWrap, isFalse, reason: title);
              expect(text.overflow, TextOverflow.fade, reason: title);
              expect(text.data, isNot(contains('\n')), reason: title);
            }
          }
          expect(tester.takeException(), isNull);
        }),
      );
    }

    testWidgets(
      'about informational details are text only and outside dismissible '
      '${brightness.name}',
      (tester) => withAppFixture(tester, (fixture) async {
        await showAbout(tester, fixture, brightness: brightness, textScale: 2);
        for (final entry in [
          ('作者', 'ThermalEX'),
          ('技术栈', 'Flutter · Dart · Material 3\nAndroid · Kotlin'),
        ]) {
          await tester.tap(await revealRow(tester, entry.$1));
          await tester.pumpAndSettle();
          final dialog = find.byType(Dialog);
          expect(dialog, findsOneWidget);
          expect(
            find.descendant(of: dialog, matching: find.text(entry.$1)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: dialog, matching: find.text(entry.$2)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialog,
              matching: find.byType(ButtonStyleButton),
            ),
            findsNothing,
          );
          expect(
            find.descendant(of: dialog, matching: find.byType(IconButton)),
            findsNothing,
          );
          final route = ModalRoute.of(tester.element(dialog))! as DialogRoute;
          expect(route.barrierDismissible, isTrue);
          expect(route.barrierColor!.a, greaterThan(0));
          expect(route.barrierColor!.a, lessThan(1));
          await tester.tapAt(const Offset(12, 12));
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          expect(tester.takeException(), isNull);
        }
      }),
    );
  }

  testWidgets('detail barrier adapts to light and dark themes', (tester) async {
    final barriers = <Color>[];
    await withAppFixture(tester, (fixture) async {
      for (final brightness in Brightness.values) {
        await showAbout(tester, fixture, brightness: brightness);
        await tester.tap(await revealRow(tester, '技术栈'));
        await tester.pumpAndSettle();
        final dialog = find.byType(Dialog);
        final route = ModalRoute.of(tester.element(dialog))! as DialogRoute;
        barriers.add(route.barrierColor!);
        final themeSurface = Theme.of(tester.element(dialog))
            .colorScheme
            .surface;
        expect(
          route.barrierColor!.withValues(alpha: 1),
          themeSurface.withValues(alpha: 1),
        );
        await tester.tapAt(const Offset(12, 12));
        await tester.pumpAndSettle();
      }
    });
    expect(barriers[0], isNot(barriers[1]));
  });

  testWidgets(
    'navigation rows retain tap and expose full text on long press',
    (tester) => withAppFixture(tester, (fixture) async {
      await showAbout(
        tester,
        fixture,
        brightness: Brightness.light,
        textScale: 2,
      );
      final github = await revealRow(tester, 'GitHub 源码仓库');
      await tester.longPress(github);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('ThermalEX/XDownloader'),
        ),
        findsOneWidget,
      );
      expect(fixture.updateBackend.pages, isEmpty);
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      await tester.tap(await revealRow(tester, 'GitHub 源码仓库'));
      await tester.pumpAndSettle();
      expect(
        fixture.updateBackend.pages.single.toString(),
        'https://github.com/ThermalEX/XDownloader',
      );
      expect(tester.takeException(), isNull);
    }),
  );
}
