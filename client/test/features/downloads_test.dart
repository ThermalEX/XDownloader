import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/features/downloads/download_tile.dart';
import 'package:xdownloader/platform/platform_bridge.dart';

import '../support/app_fixture.dart';
import '../support/fake_video_platform.dart';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late VideoPlayerPlatform previous;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = FakeVideoPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          if (call.method == 'beginPlaybackControls' ||
              call.method == 'readPlaybackControls') {
            return {'brightness': 0.5, 'volume': 0.5, 'volumeFixed': false};
          }
          return null;
        });
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });
  testWidgets(
    'batch record removal preserves every selected video file',
    (tester) => withAppFixture(tester, (fixture) async {
      for (final id in ['a', 'b']) {
        await fixture.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '$id.mp4',
            headers: const {},
            mediaIndex: 1,
          ),
        );
        fixture.backend.emit(
          BackendTaskSnapshot(
            taskId: id,
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
      }
      await fixture.downloads.reconcile();
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除记录'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records, isEmpty);
      expect(fixture.backend.saved.keys, containsAll(['a', 'b']));
      await fixture.downloads.reconcile();
      expect(fixture.downloads.records, isEmpty);
    }),
  );
  testWidgets(
    'batch partial failure keeps failed selection and fits narrow large text',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final id in ['a', 'b']) {
        await fixture.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '$id.mp4',
            headers: const {},
            mediaIndex: 1,
          ),
        );
        fixture.backend.emit(
          BackendTaskSnapshot(
            taskId: id,
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
      }
      await fixture.downloads.reconcile();
      fixture.backend.failDeletionFor.add(fixture.backend.saved['b']!.locator);
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除所选文件'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除文件'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.downloads.records.single.taskId, 'b');
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.textContaining('1 项未能完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }),
  );
  testWidgets(
    'long press selects multiple terminal downloads and batch deletion confirms once',
    (tester) => withAppFixture(tester, (fixture) async {
      for (final id in ['a', 'b']) {
        await fixture.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '$id.mp4',
            headers: const {},
            mediaIndex: 1,
          ),
        );
        fixture.backend.emit(
          BackendTaskSnapshot(
            taskId: id,
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
      }
      await fixture.downloads.reconcile();
      await fixture.downloads.start(
        DownloadRequest(
          taskId: 'active',
          url: Uri.parse('https://video.twimg.com/active.mp4'),
          displayName: 'active.mp4',
          headers: const {},
          mediaIndex: 1,
        ),
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('download_a')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      await tester.tap(find.byTooltip('删除所选文件'));
      await tester.pumpAndSettle();
      expect(find.text('删除 2 个下载文件？'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除文件'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.downloads.records.single.taskId, 'active');
      expect(fixture.backend.saved, isEmpty);
    }),
  );
  testWidgets(
    'individual menu confirms file deletion and preserves other downloads',
    (tester) => withAppFixture(tester, (fixture) async {
      for (final id in ['a', 'b']) {
        await fixture.downloads.start(
          DownloadRequest(
            taskId: id,
            url: Uri.parse('https://video.twimg.com/$id.mp4'),
            displayName: '$id.mp4',
            headers: const {},
            mediaIndex: 1,
          ),
        );
        fixture.backend.emit(
          BackendTaskSnapshot(
            taskId: id,
            phase: BackendPhase.transferred,
            bytes: 8,
          ),
        );
      }
      await fixture.downloads.reconcile();
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('download_a')),
          matching: find.byTooltip('下载操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      expect(find.text('删除下载文件？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records, hasLength(2));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('download_a')),
          matching: find.byTooltip('下载操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records.single.taskId, 'b');
      expect(fixture.backend.saved.containsKey('a'), isFalse);
      expect(fixture.backend.saved.containsKey('b'), isTrue);
    }),
  );
  testWidgets(
    'single-record removal keeps its file',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(
        DownloadRequest(
          taskId: 'a',
          url: Uri.parse('https://video.twimg.com/a.mp4'),
          displayName: 'a.mp4',
          headers: const {},
          mediaIndex: 1,
        ),
      );
      fixture.backend.emit(
        const BackendTaskSnapshot(
          taskId: 'a',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await fixture.downloads.reconcile();
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('download_a')),
          matching: find.byTooltip('下载操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除记录'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records, isEmpty);
      expect(fixture.backend.saved.containsKey('a'), isTrue);
    }),
  );
  testWidgets('missing file status and errors use friendly text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadTile(
            record: DownloadRecord(
              request: DownloadRequest(
                taskId: 'missing',
                url: Uri(),
                displayName: 'missing.mp4',
                headers: const {},
                mediaIndex: 1,
              ),
              phase: DownloadPhase.completed,
              createdAt: DateTime(2026),
              error: const AppFailure(
                FailureKind.fileMissing,
                '文件不存在或已被移走',
                'java.io.FileNotFoundException: content://media/external/downloads/837',
              ),
            ),
            onOpen: () {},
            onCancel: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('文件已不存在'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
    expect(find.textContaining('java.io'), findsNothing);
  });
  testWidgets('unlocatable legacy history is visibly distinguished', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadTile(
            record: DownloadRecord(
              request: DownloadRequest(
                taskId: 'legacy',
                url: Uri(),
                displayName: 'old.mp4',
                headers: const {},
                mediaIndex: 1,
              ),
              phase: DownloadPhase.completed,
              createdAt: DateTime(2026),
              legacy: true,
            ),
            onOpen: () {},
            onCancel: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('旧记录 · 无法定位文件'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
  });
  testWidgets(
    'off-page completion reconciles and previews the exact saved file',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(
        DownloadRequest(
          taskId: 'a',
          url: Uri.parse('https://video.twimg.com/a.mp4'),
          displayName: 'a.mp4',
          headers: const {},
          mediaIndex: 1,
        ),
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      fixture.backend.emit(
        const BackendTaskSnapshot(
          taskId: 'a',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      expect(find.text('已保存'), findsOneWidget);
      await tester.tap(find.byKey(const Key('download_a')));
      await tester.pumpAndSettle();
      expect(
        fixture.backend.previewed.single.locator,
        fixture.downloads.records.single.savedFile!.locator,
      );
    }),
  );
  testWidgets(
    'cancel and retry update repository state',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.downloads.start(
        DownloadRequest(
          taskId: 'a',
          url: Uri.parse('https://video.twimg.com/a.mp4'),
          displayName: 'a.mp4',
          headers: const {},
          mediaIndex: 1,
        ),
      );
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel_a')));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records.single.phase, DownloadPhase.cancelled);
      await tester.tap(find.byKey(const Key('retry_a')));
      await tester.pumpAndSettle();
      expect(
        fixture.downloads.records.where((r) => !r.phase.terminal),
        hasLength(1),
      );
    }),
  );
}
