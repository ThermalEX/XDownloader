import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app_theme.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/home/media_result_view.dart';

import '../support/app_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'post panel and header ink stay rounded in $brightness at ${scale}x',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(const AppSettings(), brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    MediaResultView(
                      result: resultFor('123456'),
                      onDownload: (_) async {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = find
              .ancestor(of: find.text('帖子信息'), matching: find.byType(ListTile))
              .first;
          void expectRoundedPanel() {
            final material = tester.widget<Material>(
              find.ancestor(of: header, matching: find.byType(Material)).first,
            );
            expect(material.clipBehavior, isNot(Clip.none));
            expect(material.shape, isNotNull);
            final bounds = Offset.zero & tester.getSize(header);
            expect(
              material.shape!.getOuterPath(bounds).contains(const Offset(1, 1)),
              isFalse,
            );
            final ink = tester.widget<InkWell>(
              find.descendant(of: header, matching: find.byType(InkWell)).first,
            );
            expect(ink.customBorder, isNotNull);
            expect(
              ink.customBorder!
                  .getOuterPath(bounds)
                  .contains(const Offset(1, 1)),
              isFalse,
            );
          }

          expect(
            find.text('https://x.com/author/status/123456'),
            findsOneWidget,
          );
          expectRoundedPanel();
          await tester.tap(find.text('帖子信息'));
          await tester.pumpAndSettle();
          expect(find.text('https://x.com/author/status/123456'), findsNothing);
          expectRoundedPanel();
          await tester.tap(find.text('帖子信息'));
          await tester.pumpAndSettle();
          expect(
            find.text('https://x.com/author/status/123456'),
            findsOneWidget,
          );
          expectRoundedPanel();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
