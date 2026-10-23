import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/repositories/cover_cache_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/features/settings/cover_cache_screen.dart';

import '../support/app_fixture.dart';

class UiCoverCache extends CoverCacheRepository {
  UiCoverCache(SettingsRepository settings)
    : super(
        root: Directory(
          '${Directory.systemTemp.path}/xdl-unused-widget-covers',
        ),
        settings: settings,
      );
  int size = 2048, clears = 0;
  @override
  int get usedBytes => size;
  @override
  List<CoverCacheEntry> get entries => size == 0
      ? []
      : [
          CoverCacheEntry(
            File('${root.path}/unused.jpg'),
            size,
            DateTime.utc(2026),
          ),
        ];
  @override
  Future<void> clear() async {
    clears++;
    size = 0;
    notifyListeners();
  }

  @override
  Future<void> setLimitMb(int value) async {
    await settings.edit((s) => s.copyWith(coverCacheLimitMb: value));
    notifyListeners();
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'cache rows share width and height with single-line text at 320dp ${brightness.name} ${scale}x',
        (tester) => withAppFixture(tester, (f) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final cache = UiCoverCache(f.settings)..size = 1234567890123456789;
          addTearDown(cache.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: CoverCacheScreen(cache: cache),
            ),
          );
          await tester.pumpAndSettle();
          final cards = find.byType(Card);
          expect(cards, findsNWidgets(2));
          final firstCard = tester.getRect(cards.at(0));
          final secondCard = tester.getRect(cards.at(1));
          expect(firstCard.left, closeTo(16, .1));
          expect(firstCard.right, closeTo(304, .1));
          expect(secondCard.left, closeTo(firstCard.left, .1));
          expect(secondCard.right, closeTo(firstCard.right, .1));
          final rows = [
            find.widgetWithText(ListTile, '已用缓存'),
            find.byKey(const Key('cover_cache_limit')),
            find.byKey(const Key('cover_cache_view')),
            find.byKey(const Key('cover_cache_clear')),
          ];
          final firstRow = tester.getRect(rows.first);
          for (final row in rows) {
            final bounds = tester.getRect(row);
            expect(bounds.left, closeTo(firstCard.left, .1));
            expect(bounds.right, closeTo(firstCard.right, .1));
            expect(bounds.height, closeTo(firstRow.height, .1));
          }
          for (final row in rows) {
            final tile = tester.widget<ListTile>(row);
            for (final text in [tile.title, tile.subtitle].whereType<Text>()) {
              expect(text.maxLines, 1);
              expect(text.softWrap, false);
              expect(text.overflow, TextOverflow.fade);
            }
          }
          expect(tester.takeException(), isNull);
        }),
      );
    }
  }
  testWidgets(
    'cache management saves custom limits, shows usage and clears only covers',
    (tester) => withAppFixture(tester, (f) async {
      final cache = UiCoverCache(f.settings);
      addTearDown(cache.dispose);
      await f.favorites.add('https://x.com/a/status/123456', title: 'keep');
      final before = f.favorites.items.single.toJson();
      await tester.pumpWidget(
        MaterialApp(home: CoverCacheScreen(cache: cache)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.0 KB · 1 张封面'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cover_cache_limit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cover_cache_limit_input')),
        '73',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(f.settings.value.coverCacheLimitMb, 73);
      expect(find.text('73 MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cover_cache_clear')));
      await tester.pumpAndSettle();
      expect(cache.clears, 1);
      expect(find.text('0.0 KB · 0 张封面'), findsOneWidget);
      expect(f.favorites.items.single.toJson(), before);
      await tester.tap(find.byKey(const Key('cover_cache_view')));
      await tester.pumpAndSettle();
      expect(find.text('还没有封面缓存'), findsOneWidget);
    }),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'cache settings fit 320dp doubled text ${brightness.name}',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final cache = UiCoverCache(f.settings);
        addTearDown(cache.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CoverCacheScreen(cache: cache),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await f.settings.edit((s) => s.copyWith(privacyMode: true));
        await tester.ensureVisible(find.byKey(const Key('cover_cache_view')));
        await tester.tap(find.byKey(const Key('cover_cache_view')));
        await tester.pumpAndSettle();
        expect(find.text('隐私模式已启动，无法查看封面'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      }),
    );
  }
}
