import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/app/dynamic_palette.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'first home waits for dynamic palette then uses it immediately',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.settings.edit((s) => s.copyWith(useDynamicColor: true));
      final colors = Completer<DynamicPalette>();
      await tester.pumpWidget(
        XDownloaderApp(
          dependencies: fixture.dependencies,
          palette: colors.future,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('nav_home')), findsNothing);
      final scheme = ColorScheme.fromSeed(seedColor: Colors.purple);
      colors.complete(DynamicPalette(light: scheme, dark: scheme));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav_home')), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byKey(const Key('nav_home'))))
            .colorScheme
            .primary,
        scheme.primary,
      );
    }),
  );
  for (final fails in [false, true]) {
    testWidgets(
      'unavailable palette completes with saved seed (failure=$fails)',
      (tester) => withAppFixture(tester, (fixture) async {
        await fixture.settings.edit(
          (s) => s.copyWith(useDynamicColor: true, seedColor: 0xFF47658A),
        );
        final colors = Completer<DynamicPalette>();
        await tester.pumpWidget(
          XDownloaderApp(
            dependencies: fixture.dependencies,
            palette: colors.future,
          ),
        );
        await tester.pump();
        if (fails) {
          colors.completeError(StateError('palette unavailable'));
        } else {
          colors.complete(const DynamicPalette());
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('nav_home')), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byKey(const Key('nav_home'))))
              .colorScheme
              .primary,
          ColorScheme.fromSeed(seedColor: const Color(0xFF47658A)).primary,
        );
      }),
    );
  }
}
