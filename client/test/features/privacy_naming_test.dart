import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/naming/file_naming.dart';
import 'package:xdownloader/features/downloads/video_preview_screen.dart';
import 'package:xdownloader/features/home/home_controller.dart';

import '../support/app_fixture.dart';

void main() {
  test(
    'privacy and filename preferences round trip with backwards defaults',
    () {
      final legacy = AppSettings.fromJson({});
      expect(legacy.privacyMode, isFalse);
      expect(legacy.fileNameTemplate, FileNaming.defaultTemplate);
      final settings = legacy.copyWith(
        privacyMode: true,
        fileNameTemplate: '{title}_{index}',
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.privacyMode, isTrue);
      expect(restored.fileNameTemplate, '{title}_{index}');
    },
  );
  test('templates validate and generate safe bounded distinct filenames', () {
    final media = resultFor('123456');
    final first = media.items.first.variants.first;
    expect(FileNaming.build(media, first), '中文作者_123456_v1_1280x720.mp4');
    expect(
      FileNaming.build(
        media,
        first,
        template: '{title}/{postId}_{index}_{width}x{height}',
      ),
      '中文视频_123456_1_1280x720.mp4',
    );
    final long = MediaResult(
      media.post,
      '😀中文' * 100,
      media.author,
      null,
      null,
      media.items,
      media.sourceId,
    );
    final name = FileNaming.build(
      long,
      media.items.last.variants.first,
      template: '{title}_{index}',
    );
    expect(utf8.encode(name).length, lessThanOrEqualTo(180));
    expect(name.endsWith('.mp4'), isTrue);
    expect(FileNaming.validateTemplate('{unknown}'), isNotNull);
    expect(FileNaming.validateTemplate('{aut{title}hor}'), isNotNull);
    expect(FileNaming.validateTemplate('{title}{author}'), isNull);
    expect(FileNaming.validateTemplate('{title'), isNotNull);
    expect(FileNaming.validateTemplate(''), isNotNull);
  });

  Future<void> seed(AppFixture fixture) async {
    await fixture.downloads.start(
      DownloadRequest(
        taskId: 'private',
        url: Uri.parse('https://video.twimg.com/p.mp4'),
        displayName: '私密名称.mp4',
        headers: const {},
        mediaIndex: 1,
      ),
    );
    fixture.backend.emit(
      BackendTaskSnapshot(
        taskId: 'private',
        phase: BackendPhase.transferred,
        bytes: 8,
      ),
    );
    await fixture.downloads.reconcile();
  }

  testWidgets(
    'privacy blurs names and blocks preview and external menu opening',
    (tester) => withAppFixture(tester, (fixture) async {
      final semantics = tester.ensureSemantics();
      try {
        await seed(fixture);
        await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
        await tester.pumpWidget(
          XDownloaderApp(dependencies: fixture.dependencies),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav_downloads')));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(find.byKey(const Key('download_private')))
              .toStringDeep(),
          isNot(contains('私密名称')),
        );
        expect(
          find.ancestor(
            of: find.text('私密名称.mp4'),
            matching: find.byType(ImageFiltered),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('download_private')));
        await tester.pumpAndSettle();
        expect(find.text('隐私模式已启动，无法查看视频'), findsOneWidget);
        expect(find.byType(VideoPreviewScreen), findsNothing);
        expect(fixture.backend.previewed, isEmpty);
        await tester.tap(find.byTooltip('下载操作'));
        await tester.pumpAndSettle();
        expect(find.text('私密名称.mp4').hitTestable(), findsNothing);
        await tester.tap(find.text('打开文件'));
        await tester.pumpAndSettle();
        expect(fixture.backend.opened, isEmpty);
      } finally {
        semantics.dispose();
      }
    }),
  );
  testWidgets(
    'privacy is rechecked when external opening waits behind file work',
    (tester) => withAppFixture(tester, (fixture) async {
      await seed(fixture);
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      final pending = Completer<void>();
      fixture.backend.beforeReadable = () => pending.future;
      final lookup = fixture.downloads.fileForPreview('private');
      await tester.pump();
      await tester.tap(find.byTooltip('下载操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开文件'));
      await tester.pump();
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      pending.complete();
      await lookup;
      await tester.pumpAndSettle();
      expect(fixture.backend.opened, isEmpty);
      expect(find.text('隐私模式已启动，无法查看视频'), findsOneWidget);
    }),
  );
  testWidgets(
    'saved filename template applies to subsequent requests',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.settings.edit(
        (s) => s.copyWith(fileNameTemplate: '{title}_{index}_{resolution}'),
      );
      final home = HomeController(fixture.dependencies);
      await home.parse('https://x.com/a/status/123456');
      await home.download(home.result!.items.first.variants.first);
      expect(
        fixture.downloads.records.single.request.displayName,
        '中文视频_1_1280x720.mp4',
      );
      home.dispose();
    }),
  );
  testWidgets(
    'privacy enabled during file lookup prevents late preview',
    (tester) => withAppFixture(tester, (fixture) async {
      await seed(fixture);
      final pending = Completer<void>();
      fixture.backend.beforeReadable = () => pending.future;
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_private')));
      await tester.pump();
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(VideoPreviewScreen), findsNothing);
      expect(find.text('隐私模式已启动，无法查看视频'), findsOneWidget);
    }),
  );
}
