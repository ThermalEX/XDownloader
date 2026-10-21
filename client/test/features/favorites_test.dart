import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'privacy hides favorites and blocks stale opening until disabled',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add(
        'https://x.com/private/status/345678',
        title: '私密收藏标题',
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final staleOpen = tester
          .widget<ListTile>(find.byKey(const Key('favorite_345678')))
          .onTap!;
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      staleOpen();
      await tester.pumpAndSettle();
      expect(fixture.parser.calls, isEmpty);
      expect(find.text('私密收藏标题'), findsNothing);
      expect(find.text('https://x.com/private/status/345678'), findsNothing);
      expect(find.byTooltip('收藏操作'), findsNothing);
      expect(find.text('隐私模式已启动，无法查看收藏'), findsWidgets);
      expect(fixture.favorites.items.single.title, '私密收藏标题');
      await fixture.settings.edit((s) => s.copyWith(privacyMode: false));
      await tester.pumpAndSettle();
      expect(find.text('私密收藏标题'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite_345678')));
      await tester.pumpAndSettle();
      expect(
        fixture.parser.calls.single,
        'https://x.com/private/status/345678',
      );
    }),
  );
  testWidgets(
    'privacy blocks copying from an already open favorites menu',
    (tester) => withAppFixture(tester, (fixture) async {
      final copies = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      try {
        await fixture.favorites.add('https://x.com/private/status/345678');
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_favorites')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('favorite_actions_345678')));
        await tester.pumpAndSettle();
        await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制链接'));
        await tester.pumpAndSettle();
        expect(copies, isEmpty);
        expect(find.text('隐私模式已启动，无法查看收藏'), findsWidgets);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    }),
  );
  testWidgets(
    'home favorites and clipboard list open the exact saved link for parsing',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://x.com/a/status/123456',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('favorite_current')));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items.single.postId, '123456');
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      fixture.clipboard = '分享 https://twitter.com/b/status/234567?s=20';
      await tester.tap(find.text('从剪贴板添加'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items, hasLength(2));
      await tester.tap(find.byKey(const Key('favorite_234567')));
      await tester.pumpAndSettle();
      expect(fixture.parser.calls.last, 'https://x.com/b/status/234567');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('中文视频'), findsOneWidget);
    }),
  );
  testWidgets(
    'manual favorite validates input and menu removal updates list',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加链接'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('favorite_input')), 'bad');
      await tester.tap(find.widgetWithText(FilledButton, '收藏'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的 X 帖子链接'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('favorite_input')),
        'https://x.com/a/status/123456',
      );
      await tester.tap(find.widgetWithText(FilledButton, '收藏'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('favorite_actions_123456')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();
      expect(fixture.favorites.items, isEmpty);
    }),
  );
}
