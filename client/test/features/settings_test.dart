import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'fields and interactive settings/source rows share rounded feedback in both themes',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await fixture.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_home')));
        await tester.pumpAndSettle();
        final field = tester.widget<InputDecorator>(
          find.byType(InputDecorator).first,
        );
        expect(
          field.decoration.border!
              .getOuterPath(const Rect.fromLTWH(0, 0, 280, 56))
              .contains(const Offset(4, 1)),
          isFalse,
        );
        await tester.tap(find.byKey(const Key('nav_settings')));
        await tester.pumpAndSettle();
        void expectRoundedRows() {
          for (final element in find.byType(ListTile).evaluate()) {
            final row = element.widget as ListTile;
            if (row.onTap == null) continue;
            final ink = tester.widget<InkWell>(
              find
                  .descendant(
                    of: find.byWidget(row),
                    matching: find.byType(InkWell),
                  )
                  .first,
            );
            expect(ink.customBorder, isNotNull);
            expect(
              ink.customBorder!
                  .getOuterPath(const Rect.fromLTWH(0, 0, 280, 72))
                  .contains(const Offset(4, 1)),
              isFalse,
            );
          }
        }

        expectRoundedRows();
        await tester.tap(find.text('规则设置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('下载源'));
        await tester.tap(find.text('下载源'));
        await tester.pumpAndSettle();
        expectRoundedRows();
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .popUntil((route) => route.isFirst);
        await tester.pumpAndSettle();
      }
    }),
  );
  testWidgets(
    'system gesture area stays transparent across theme and route changes',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await fixture.settings.edit((s) => s.copyWith(themeMode: mode));
        await tester.pumpAndSettle();
        expect(
          SystemChrome.latestStyle?.systemNavigationBarContrastEnforced,
          isFalse,
        );
        expect(
          SystemChrome.latestStyle?.systemNavigationBarColor,
          Colors.transparent,
        );
        expect(
          SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
          mode == AppThemeMode.dark ? Brightness.light : Brightness.dark,
        );
      }
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('下载源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载源'));
      await tester.pumpAndSettle();
      expect(
        SystemChrome.latestStyle?.systemNavigationBarContrastEnforced,
        isFalse,
      );
      expect(
        SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
        Brightness.light,
      );
    }),
  );
  testWidgets(
    'theme, color, dynamic color and clipboard use persistent settings',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      expect(find.text('主题颜色'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '湖蓝'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '森林绿'), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme_mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色').last);
      await tester.pumpAndSettle();
      expect(fixture.settings.value.themeMode, AppThemeMode.dark);
      await tester.tap(find.byTooltip('蓝色主题'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.seedColor, 0xFF47658A);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '湖蓝'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('动态取色'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.useDynamicColor, isTrue);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      expect(find.text('下载源'), findsOneWidget);
      expect(find.text('失败后自动换源'), findsNothing);
      await tester.tap(find.text('下载源'));
      await tester.pumpAndSettle();
      expect(find.text('失败后自动换源'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.text('自动读取剪贴板'), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      expect(find.text('下载源'), findsNothing);
      expect(find.text('失败后自动换源'), findsNothing);
      await tester.tap(find.text('自动读取剪贴板'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.autoClipboard, isTrue);
    }),
  );
  testWidgets(
    'source selection fallback and custom validation work through repositories',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('失败后自动换源'));
      await tester.pumpAndSettle();
      expect(fixture.sources.autoFallback, isFalse);
      await tester.tap(find.text('FxTwitter'));
      await tester.pumpAndSettle();
      expect(fixture.sources.currentId, 'fx');
      await tester.tap(find.byTooltip('添加解析源'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('source_name')), '测试源');
      await tester.enterText(
        find.byKey(const Key('source_endpoint')),
        'file:///bad',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(fixture.sources.list.length, SourceCatalog.builtins.length);
      await tester.enterText(
        find.byKey(const Key('source_endpoint')),
        'https://source.test/?url={urlenc}',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(fixture.sources.list.length, SourceCatalog.builtins.length + 1);
    }),
  );
  testWidgets(
    'all tabs fit 320dp and doubled text in light and dark themes',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await fixture.settings.update(
          fixture.settings.value.copyWith(themeMode: mode),
        );
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        for (final tab in ['home', 'downloads', 'favorites', 'settings']) {
          await tester.tap(find.byKey(Key('nav_$tab')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$mode/$tab');
        }
        await tester.ensureVisible(find.text('外观设置'));
        await tester.tap(find.text('外观设置'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('动态取色'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull, reason: '$mode/appearance');
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
    }),
  );
}
