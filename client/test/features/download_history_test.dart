import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/features/downloads/download_history_screen.dart';

import '../support/app_fixture.dart';

DownloadRequest historyRequest(String id, {bool link = true}) =>
    DownloadRequest(
      taskId: id,
      url: Uri.parse('https://video.twimg.com/$id.mp4'),
      displayName: 'private-$id.mp4',
      headers: const {},
      mediaIndex: 1,
      postUrl: link ? Uri.parse('https://x.com/author/status/123456') : null,
    );

void main() {
  testWidgets(
    'file_delete_keeps_history_and_reparse_uses_post_url',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(historyRequest('a'));
      fixture.backend.emit(
        const BackendTaskSnapshot(
          taskId: 'a',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await fixture.downloads.reconcile();
      await fixture.downloads.deleteFile('a');
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_history')));
      await tester.pumpAndSettle();
      expect(find.text('private-a.mp4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('history_a')));
      await tester.pumpAndSettle();
      expect(
        fixture.parser.calls,
        contains('https://x.com/author/status/123456'),
      );
      expect(find.text('下载历史'), findsNothing);
    }),
  );
  testWidgets(
    'history_clear_never_deletes_saved_files',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(historyRequest('a'));
      fixture.backend.emit(
        const BackendTaskSnapshot(
          taskId: 'a',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await fixture.downloads.reconcile();
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadHistoryScreen(
            repository: fixture.downloads,
            settings: fixture.settings,
            onParse: (_) {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('清空历史'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.downloads.history, hasLength(1));
      await tester.tap(find.byTooltip('清空历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.history, isEmpty);
      expect(fixture.backend.saved, contains('a'));
    }),
  );
  testWidgets(
    'privacy_toggle_blocks_open_menu_actions_and_semantics',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(historyRequest('a'));
      await fixture.downloads.cancel('a');
      final parsed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadHistoryScreen(
            repository: fixture.downloads,
            settings: fixture.settings,
            onParse: parsed.add,
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      await tester.tap(find.byKey(const Key('history_actions_a')));
      await tester.pumpAndSettle();
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新解析'));
      await tester.pumpAndSettle();
      expect(parsed, isEmpty);
      expect(find.text('private-a.mp4'), findsNothing);
      expect(find.textContaining('https://x.com'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('private-a|https://x.com')),
        findsNothing,
      );
      expect(find.textContaining('隐私模式'), findsOneWidget);
      semantics.dispose();
    }),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'history supports narrow large text ${brightness.name}',
      (tester) => withAppFixture(tester, (fixture) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fixture.downloads.start(historyRequest('missing', link: false));
        await fixture.downloads.cancel('missing');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: brightness,
              ),
            ),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: DownloadHistoryScreen(
              repository: fixture.downloads,
              settings: fixture.settings,
              onParse: (_) => fail('missing link'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('没有原帖子链接，无法重新解析'), findsOneWidget);
        await tester.tap(find.text('成功'));
        await tester.pumpAndSettle();
        expect(find.text('没有符合条件的历史'), findsOneWidget);
      }),
    );
  }
}
