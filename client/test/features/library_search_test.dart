import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/download_history.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/features/downloads/downloads_screen.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'old downloads can search the original link retained in history',
    (tester) => withAppFixture(tester, (f) async {
      final store = MemorySnapshotStore();
      final now = DateTime.utc(2026, 10, 23);
      await store.write('downloads', {
        'records': [
          DownloadRecord(
            request: DownloadRequest(
              taskId: 'old',
              url: Uri.parse('https://video.twimg.com/old.mp4'),
              displayName: '旧视频.mp4',
              headers: const {},
              mediaIndex: 1,
            ),
            phase: DownloadPhase.completed,
            createdAt: now,
            legacy: true,
          ).toJson(),
        ],
        'historyVersion': 1,
        'history': [
          DownloadHistoryEntry(
            taskId: 'old',
            displayName: '旧视频.mp4',
            postUrl: Uri.parse('https://x.com/history/status/234567'),
            createdAt: now,
            finishedAt: now,
            phase: DownloadPhase.completed,
          ).toJson(),
        ],
      });
      final repo = DownloadRepository(store: store, backend: f.backend);
      await repo.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsScreen(
              repository: repo,
              settings: f.settings,
              favorites: f.favorites,
              onParse: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('downloads_search')),
        '234567',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download_old')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    }),
  );
  testWidgets(
    'search combines categories, clears, and resets on privacy',
    (tester) => withAppFixture(tester, (f) async {
      await f.favorites.add('https://x.com/a/status/123456', title: 'Music 猫');
      await f.favorites.add('https://x.com/b/status/234567', title: 'Other 猫');
      await f.favorites.update('123456', title: 'Music 猫', category: 'Music');
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('favorites_search'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'MUSIC 猫');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
      expect(find.byKey(const Key('favorite_234567')), findsNothing);
      await tester.enterText(field, '234567');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_234567')), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite_category:Music')));
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的结果'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favorite_category_all')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('favorite_234567')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      await f.settings.edit((s) => s.copyWith(privacyMode: false));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.byKey(const Key('favorite_123456')), findsOneWidget);
    }),
  );

  testWidgets(
    'downloads and history search filename and original post URL',
    (tester) => withAppFixture(tester, (f) async {
      for (final id in ['123456', '234567']) {
        await f.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '$id 猫.mp4',
            headers: const {},
            mediaIndex: 1,
            postUrl: Uri.parse('https://x.com/a/status/$id'),
          ),
        );
        await f.downloads.cancel(id);
      }
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      for (final page in ['downloads', 'history']) {
        if (page == 'history') {
          await tester.tap(find.byKey(const Key('download_history')));
          await tester.pumpAndSettle();
        }
        final field = find.byKey(Key('${page}_search'));
        expect(field, findsOneWidget);
        await tester.enterText(field, 'x.com 123456');
        await tester.pumpAndSettle();
        final prefix = page == 'history' ? 'history' : 'download';
        expect(find.byKey(Key('${prefix}_123456')), findsOneWidget);
        expect(find.byKey(Key('${prefix}_234567')), findsNothing);
        if (page == 'downloads') {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          await tester.longPress(find.byKey(const Key('download_123456')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('全选'));
          await tester.pumpAndSettle();
          expect(find.text('已选 1 项'), findsOneWidget);
        }
        await tester.enterText(field, '不存在');
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的结果'), findsOneWidget);
        expect(find.text('已选 1 项'), findsNothing);
        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('${prefix}_234567')), findsOneWidget);
        await tester.enterText(field, 'secret');
        await tester.pumpAndSettle();
        await f.settings.edit((s) => s.copyWith(privacyMode: true));
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        await f.settings.edit((s) => s.copyWith(privacyMode: false));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      }
    }),
  );
}
