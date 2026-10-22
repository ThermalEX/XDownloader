import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/app/dynamic_palette.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/app_update.dart';

import '../test/support/app_fixture.dart';
import '../test/support/update_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'dynamic surfaces category management tag dragging and anchored messages',
    (tester) => withAppFixture(tester, (f) async {
      // Isolated repositories/parser/update backend. No real media or APK download.
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await File('${Directory.systemTemp.path}/xdl_probe_$name.png')
            .writeAsBytes(await binding.takeScreenshot(name));
      }

      Future<void> tap(Finder finder) async {
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> hold(Finder finder) async {
        final gesture = await tester.startGesture(tester.getCenter(finder));
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      Future<void> reveal(Finder finder, {double delta = 180}) async {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();
      }

      await f.settings.edit(
        (s) => s.copyWith(
          themeMode: AppThemeMode.dark,
          useDynamicColor: true,
          useOriginalFileName: false,
          fileNameTemplate: '{title}_{date}',
        ),
      );
      for (final (id, category) in [
        ('123456', 'A'),
        ('234567', 'A'),
        ('345678', 'C'),
      ]) {
        await f.favorites.add(
          'https://x.com/demo/status/$id',
          title: '示例收藏 $id',
        );
        await f.favorites.update(id, title: '示例收藏 $id', category: category);
      }
      final palette = await loadDynamicPalette();
      debugPrint('OS dynamic palette available: ${palette.dark != null}');
      await tester.pumpWidget(
        XDownloaderApp(
          dependencies: f.dependencies,
          palette: Future.value(palette),
        ),
      );
      await tester.pumpAndSettle();
      final colors = Theme.of(tester.element(find.byType(NavigationBar)))
          .colorScheme;
      expect(colors.surface, isNot(colors.surfaceContainerLow));
      await binding.convertFlutterSurfaceToImage();
      await tap(find.byKey(const Key('nav_settings')));
      await capture('dynamic_sections');
      await reveal(find.text('关于'));
      await tap(find.text('关于'));
      await reveal(find.byKey(const Key('changelog_entry')));
      await tap(find.byKey(const Key('changelog_entry')));
      await capture('changelog_markdown');
      await tap(find.byType(BackButton));
      await tap(find.byType(BackButton));

      await tap(find.byKey(const Key('nav_favorites')));
      await hold(find.byKey(const Key('favorite_category:A')));
      await tester.pumpAndSettle();
      await capture('category_actions');
      await tap(find.text('编辑名称'));
      await tester.enterText(
        find.byKey(const Key('favorite_category_name')),
        '音乐',
      );
      await tap(find.widgetWithText(FilledButton, '保存'));
      expect(f.favorites.items.where((i) => i.category == '音乐'), hasLength(2));
      await tap(find.byKey(const Key('favorite_category:音乐')));
      await hold(find.byKey(const Key('favorite_123456')));
      await tester.pumpAndSettle();
      await tap(find.text('全选'));
      await capture('favorite_multi_selection');
      await tap(find.byKey(const Key('favorite_delete_selected')));
      await tap(find.widgetWithText(FilledButton, '删除收藏'));
      expect(f.favorites.items.single.postId, '345678');
      await tap(find.text('撤回'));
      expect(f.favorites.items, hasLength(3));
      await capture('favorites_after_undo');
      await tester.ensureVisible(find.byKey(const Key('favorite_category:音乐')));
      await tester.pumpAndSettle();
      await hold(find.byKey(const Key('favorite_category:音乐')));
      await tester.pumpAndSettle();
      await capture('category_delete_actions');
      await tap(find.text('删除分类'));
      await tap(find.widgetWithText(FilledButton, '删除分类'));
      expect(f.favorites.items.where((i) => i.category.isEmpty), hasLength(2));

      await tap(find.byKey(const Key('nav_settings')));
      await reveal(find.text('规则设置'), delta: -180);
      await tap(find.text('规则设置'));
      await tap(find.text('重命名规则'));
      final title = find.byKey(const Key('naming_field_0'));
      final date = find.byKey(const Key('naming_field_1'));
      final target = tester.getCenter(title);
      final gesture = await tester.startGesture(tester.getCenter(date));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
      await gesture.moveTo(target);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await capture('naming_dragged_tags');
      final separator = find.byKey(const Key('naming_separator'));
      await reveal(separator);
      await tester.enterText(separator, '-');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('naming_separator_preview');
      await reveal(find.text('保存'));
      await tap(find.text('保存'));
      expect(f.settings.value.fileNameTemplate, '{date}-{title}');
      await tap(find.byType(BackButton));

      final sample = fixtureUpdate();
      final update = UpdateRelease(
        releaseId: sample.releaseId,
        tag: sample.tag,
        releasePage: sample.releasePage,
        notes: '# 版本更新\n\n## 主要更新\n\n- **分类管理**：长按编辑名称或删除分类。\n- **命名标签**：点选添加，长按拖动排序。\n- 更新弹窗更宽，分区与提示位置更清楚。\n\n[查看发布记录](https://github.com/ThermalEX/XDownloader/releases)',
        versionName: sample.versionName,
        versionCode: sample.versionCode,
        channel: sample.channel,
        packageName: sample.packageName,
        minSdk: sample.minSdk,
        assets: sample.assets,
      );
      f.releaseClient.respond = (_) async => ReleaseCheck(
        candidate: update,
        scopeComplete: true,
        skippedReleases: 0,
        validReleases: 1,
      );
      await f.updates.check();
      await tester.pumpAndSettle();
      await tap(find.byTooltip('发现新版本'));
      await capture('update_markdown');
      await reveal(find.byKey(const Key('update_dialog_release_page')));
      await capture('update_wide_dialog');
      await tap(find.text('不再提醒'));
      expect(f.updates.preferences.showUpdatePrompt, false);
      await tap(find.text('关闭'));

      f.shareEvents.add('https://x.com/demo/status/456789');
      await tester.pumpAndSettle();
      await tap(find.byKey(const Key('favorite_current')));
      final homeBottom = tester.getBottomLeft(find.byType(SnackBar)).dy;
      await capture('home_message_baseline');
      await tap(find.byKey(const Key('nav_downloads')));
      expect(
        tester.getBottomLeft(find.byType(SnackBar)).dy,
        closeTo(homeBottom, 1),
      );
      await capture('downloads_message_baseline');
      await tester.drag(find.byType(SnackBar), const Offset(0, 180));
      await tester.pumpAndSettle();
      await tap(find.byKey(const Key('nav_home')));
      final input = find.byKey(const Key('home_link_input'));
      await tester.showKeyboard(input);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final inset = MediaQuery.viewInsetsOf(tester.element(input)).bottom;
      debugPrint('Native IME inset: $inset');
      ScaffoldMessenger.of(tester.element(input))
          .showSnackBar(const SnackBar(content: Text('输入法上方的消息示例')));
      await tester.pumpAndSettle();
      if (inset > 0) {
        expect(
          tester.getBottomLeft(find.byType(SnackBar)).dy,
          lessThanOrEqualTo(
            MediaQuery.sizeOf(tester.element(input)).height - inset,
          ),
        );
      }
      await capture('keyboard_message_baseline');
      FocusManager.instance.primaryFocus?.unfocus();
      expect(tester.takeException(), isNull);
    }),
  );
}
