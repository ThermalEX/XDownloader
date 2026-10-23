import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/features/downloads/video_thumbnail.dart';

import '../support/app_fixture.dart';

Future<void> openFavorites(WidgetTester tester, AppFixture fixture) async {
  await tester.pumpWidget(XDownloaderApp(dependencies: fixture.dependencies));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav_favorites')));
  await tester.pumpAndSettle();
}

Future<void> openDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('favorite_actions_123456')));
  await tester.pumpAndSettle();
  expect(find.text('详情'), findsOneWidget);
  await tester.tap(find.text('详情'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'favorite shows only name and unobscured thumbnail before menu and heart',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.favorites.add(
        'https://x.com/author/status/123456',
        title: '收藏名称',
      );
      await fixture.favorites.update('123456', title: '收藏名称', category: '秘密分类');
      await openFavorites(tester, fixture);
      final tile = tester.widget<ListTile>(
        find.byKey(const Key('favorite_123456')),
      );
      expect(tile.subtitle, isNull);
      final menu = find.byKey(const Key('favorite_actions_123456'));
      final heart = find.byKey(const Key('favorite_remove_123456'));
      final thumbnail = find.descendant(
        of: find.byKey(const Key('favorite_123456')),
        matching: find.byType(VideoThumbnail),
      );
      expect(
        tester.getRect(thumbnail).right,
        lessThan(tester.getRect(menu).left),
      );
      expect(
        tester.getRect(menu).right,
        lessThanOrEqualTo(tester.getRect(heart).left),
      );
      expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(menu).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(heart).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(heart).height, greaterThanOrEqualTo(48));
    }),
  );

  testWidgets(
    'details shows three one-line values and copies their full contents',
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
        await fixture.favorites.add(
          'https://x.com/author/status/123456',
          title: '收藏名称',
        );
        await openFavorites(tester, fixture);
        await openDetails(tester);
        for (final entry in {
          'name': '收藏名称',
          'url': 'https://x.com/author/status/123456',
          'author': 'author',
        }.entries) {
          final row = find.byKey(Key('favorite_detail_${entry.key}'));
          expect(row, findsOneWidget);
          final value = tester.widget<Text>(
            find.descendant(of: row, matching: find.text(entry.value)),
          );
          expect(value.maxLines, 1);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(copies.last, entry.value);
        }
        expect(fixture.parser.calls, isEmpty);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    }),
  );

  testWidgets(
    'parsed author appears in details and long names copy in full',
    (tester) => withAppFixture(tester, (fixture) async {
      final title = List.filled(20, '完整收藏名称').join();
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
        await fixture.favorites.add(
          'https://x.com/account/status/123456',
          title: title,
          author: '解析作者显示名',
        );
        await openFavorites(tester, fixture);
        await openDetails(tester);
        expect(find.text('解析作者显示名'), findsOneWidget);
        await tester.tap(find.byKey(const Key('favorite_detail_name')));
        await tester.pumpAndSettle();
        expect(copies.single, title);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    }),
  );

  testWidgets(
    'privacy hides already open details and rejects stale copy callbacks',
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
        await fixture.favorites.add(
          'https://x.com/author/status/123456',
          title: '私密收藏',
        );
        await openFavorites(tester, fixture);
        await openDetails(tester);
        final staleCopy = tester
            .widget<InkWell>(find.byKey(const Key('favorite_detail_url')))
            .onTap!;
        await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
        await tester.pumpAndSettle();
        staleCopy();
        await tester.pumpAndSettle();
        expect(copies, isEmpty);
        expect(find.text('私密收藏'), findsNothing);
        expect(find.text('https://x.com/author/status/123456'), findsNothing);
        expect(find.text('author'), findsNothing);
        expect(find.byKey(const Key('favorite_detail_url')), findsNothing);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    }),
  );

  testWidgets(
    'long details and action row fit 320dp with doubled text in both themes',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await fixture.favorites.add(
        'https://x.com/i/status/123456',
        title: List.filled(30, '很长的收藏名称').join(),
      );
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await fixture.settings.edit((s) => s.copyWith(themeMode: mode));
        await openFavorites(tester, fixture);
        expect(tester.takeException(), isNull);
        await openDetails(tester);
        expect(find.text('未记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
    }),
  );
}
