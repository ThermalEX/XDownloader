import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/app/dynamic_palette.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/features/settings/app_update_dialog.dart';
import 'package:xdownloader/features/settings/naming_settings_screen.dart';
import 'package:xdownloader/features/favorites/favorites_screen.dart';

import '../support/app_fixture.dart';
import '../support/update_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'selection and naming tags fit 320dp doubled text $brightness',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget host(Widget child) => MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: child,
        );
        await f.favorites.add('https://x.com/a/status/123456', title: '长标题示例');
        await tester.pumpWidget(
          host(
            Scaffold(
              body: FavoritesScreen(
                dependencies: f.dependencies,
                onOpen: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byKey(const Key('favorite_123456')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('全选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('favorite_delete_selected')));
        await tester.pumpAndSettle();
        expect(find.text('删除 1 项收藏？'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await f.settings.edit(
          (s) => s.copyWith(
            useOriginalFileName: false,
            fileNameTemplate: '{title}',
          ),
        );
        await tester.pumpWidget(
          host(NamingSettingsScreen(repository: f.settings)),
        );
        await tester.pumpAndSettle();
        for (final key in ['naming_add_date', 'naming_separator']) {
          final control = find.byKey(Key(key));
          await tester.scrollUntilVisible(
            control,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          if (key == 'naming_add_date') {
            await tester.tap(control);
          } else {
            await tester.enterText(control, '-');
          }
          await tester.pumpAndSettle();
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.scrollUntilVisible(
          find.text('保存'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      }),
    );
  }
  testWidgets(
    'category keyboard closes before a smooth navigation return and stale selection respects privacy',
    (tester) => withAppFixture(tester, (f) async {
      addTearDown(tester.view.resetViewInsets);
      await f.favorites.add('https://x.com/a/status/123456', title: '私密收藏');
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_add_category')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '分类',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final transition = find.byKey(const Key('root_navigation_transition'));
      final middle = tester.getSize(transition).height;
      expect(middle, greaterThan(0));
      await tester.pumpAndSettle();
      expect(middle, lessThan(tester.getSize(transition).height));
      await tester.longPress(find.byKey(const Key('favorite_123456')));
      await tester.pumpAndSettle();
      final stale = tester
          .widget<IconButton>(find.byKey(const Key('favorite_delete_selected')))
          .onPressed!;
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      stale();
      await tester.pumpAndSettle();
      expect(f.favorites.items, hasLength(1));
      expect(find.text('私密收藏'), findsNothing);
      expect(find.text('删除收藏'), findsNothing);
    }),
  );
  testWidgets(
    'naming buttons separator and dragging save a composed rule',
    (tester) => withAppFixture(tester, (f) async {
      await f.settings.edit(
        (s) =>
            s.copyWith(useOriginalFileName: false, fileNameTemplate: '{title}'),
      );
      await tester.pumpWidget(
        MaterialApp(home: NamingSettingsScreen(repository: f.settings)),
      );
      await tester.pumpAndSettle();
      final add = find.byKey(const Key('naming_add_date'));
      await tester.scrollUntilVisible(
        add,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final separator = find.byKey(const Key('naming_separator'));
      await tester.ensureVisible(separator);
      await tester.pumpAndSettle();
      await tester.enterText(separator, '-');
      await tester.pumpAndSettle();
      final tags = find.byKey(const Key('naming_order'));
      await tester.scrollUntilVisible(
        tags,
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final date = find.byKey(const Key('naming_field_1'));
      final title = find.byKey(const Key('naming_field_0'));
      final gesture = await tester.startGesture(tester.getCenter(date));
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.moveTo(tester.getCenter(title));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.textContaining('示例视频.mp4'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('保存'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(f.settings.value.fileNameTemplate, '{date}-{title}');
    }),
  );
  test('legacy dynamic surface collision is repaired without changing accent colors', () {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      final legacy = scheme.copyWith(surface: scheme.surfaceContainerLow);
      final fixed = dynamicSurfaces(
        legacy,
        (tone) => Color.fromRGBO(
          (tone * 2.55).round(),
          (tone * 2.55).round(),
          (tone * 2.55).round(),
          1,
        ),
      );
      expect(fixed.surface, isNot(fixed.surfaceContainerLow));
      expect(fixed.surfaceContainerLow, isNot(fixed.surfaceContainerHigh));
      expect(fixed.primary, legacy.primary);
      expect(
        ThemeData(colorScheme: fixed).scaffoldBackgroundColor,
        fixed.surface,
      );
    }
  });
  testWidgets(
    'update window uses wider margins and places suppression beside browser action',
    (tester) => withAppFixture(tester, (f) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      f.releaseClient.respond = (_) async => ReleaseCheck(
        candidate: fixtureUpdate(),
        scopeComplete: true,
        skippedReleases: 0,
        validReleases: 1,
      );
      await f.updates.check();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppUpdateDialog(repository: f.updates)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AlertDialog)).width,
        greaterThanOrEqualTo(360),
      );
      final reminder = tester.getRect(find.text('不再提醒'));
      final browser = tester.getRect(find.text('前往发布页'));
      expect(reminder.center.dy, closeTo(browser.center.dy, 4));
      await tester.tap(find.text('不再提醒'));
      await tester.pumpAndSettle();
      expect(f.updates.preferences.showUpdatePrompt, false);
      await tester.tap(find.text('前往发布页'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.pages, hasLength(1));
    }),
  );
  testWidgets(
    'home and downloads messages have the same baseline and move above the keyboard',
    (tester) => withAppFixture(tester, (f) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final root = tester.element(find.byType(NavigationBar));
      ScaffoldMessenger.of(root).showSnackBar(
        const SnackBar(content: Text('测试消息'), duration: Duration(seconds: 30)),
      );
      await tester.pumpAndSettle();
      final home = tester.getBottomLeft(find.byType(SnackBar)).dy;
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.byType(SnackBar)).dy, closeTo(home, 1));
      await tester.tap(find.byKey(const Key('nav_home')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(SnackBar)).dy,
        lessThanOrEqualTo(540),
      );
    }),
  );
  testWidgets(
    'long press category edits or deletes classification without removing favorites',
    (tester) => withAppFixture(tester, (f) async {
      await f.favorites.add('https://x.com/a/status/123456', title: '标题');
      await f.favorites.update('123456', title: '标题', category: '旧分类');
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('favorite_category:旧分类')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑名称'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '新分类',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(f.favorites.items.single.category, '新分类');
      await tester.longPress(find.byKey(const Key('favorite_category:新分类')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除分类'));
      await tester.pumpAndSettle();
      expect(f.favorites.items.single.category, '');
      expect(f.favorites.categories, isEmpty);
    }),
  );
  testWidgets(
    'long press favorites selects visible items only and batch removal can be undone',
    (tester) => withAppFixture(tester, (f) async {
      for (final (id, group) in [
        ('123456', 'A'),
        ('234567', 'A'),
        ('345678', 'B'),
      ]) {
        await f.favorites.add('https://x.com/a/status/$id', title: id);
        await f.favorites.update(id, title: id, category: group);
      }
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_category:A')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('favorite_123456')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite_delete_selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除收藏'));
      await tester.pumpAndSettle();
      expect(f.favorites.items.single.postId, '345678');
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(f.favorites.items, hasLength(3));
      expect(f.parser.calls, isEmpty);
      await tester.longPress(find.byKey(const Key('favorite_category:A')));
      await tester.pumpAndSettle();
      expect(find.text('删除分类'), findsOneWidget);
    }),
  );
}
