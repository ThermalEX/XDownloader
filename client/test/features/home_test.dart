import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/features/home/home_controller.dart';

import '../support/app_fixture.dart';

void main() {
  late AppFixture fixture;
  setUp(() async {
    fixture = AppFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.close());
  test('new share wins over a stale parse', () async {
    final a = Completer<MediaResult>(), b = Completer<MediaResult>();
    fixture.parser.respond = (input, _) =>
        input.contains('123456') ? a.future : b.future;
    final controller = HomeController(fixture.dependencies);
    final first = controller.parse('https://x.com/a/status/123456');
    final second = controller.acceptSharedText('https://x.com/b/status/222222');
    b.complete(resultFor('222222'));
    await second;
    a.complete(resultFor('123456'));
    await first;
    expect(controller.result?.post.postId, '222222');
    expect(controller.input, contains('222222'));
    controller.dispose();
  });
  test(
    'automatic clipboard does not read when disabled or replace edited input',
    () async {
      fixture.clipboard = 'https://x.com/a/status/123456';
      final controller = HomeController(fixture.dependencies);
      await controller.onResumed();
      expect(fixture.clipboardReads, 0);
      expect(controller.input, isEmpty);
      await fixture.settings.edit((s) => s.copyWith(autoClipboard: true));
      controller.setInput('手动输入');
      await controller.onResumed();
      expect(controller.input, '手动输入');
      expect(fixture.parser.calls, isEmpty);
      controller.clear();
      await controller.onResumed();
      expect(controller.result?.post.postId, '123456');
      controller.clear();
      await controller.onResumed();
      expect(controller.result, isNull);
      controller.dispose();
    },
  );
  test(
    'clear, leaving home and dispose invalidate unfinished requests',
    () async {
      for (final action in ['clear', 'leave', 'dispose']) {
        final pending = Completer<MediaResult>();
        fixture.parser.respond = (_, _) => pending.future;
        final controller = HomeController(fixture.dependencies);
        final work = controller.parse('https://x.com/a/status/123456');
        expect(controller.busy, isTrue);
        if (action == 'clear') controller.clear();
        if (action == 'leave') controller.setVisible(false);
        if (action == 'dispose') controller.dispose();
        pending.complete(resultFor('123456'));
        await work;
        expect(controller.result, isNull);
        if (action != 'dispose') controller.dispose();
      }
    },
  );
  testWidgets(
    'explicit share returns from a settings subpage to the new result',
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
      fixture.shareEvents.add('https://x.com/author/status/222222');
      await tester.pumpAndSettle();
      expect(find.text('中文视频'), findsOneWidget);
      expect(find.byTooltip('添加解析源'), findsNothing);
    }),
  );
  testWidgets(
    'paste parse groups and immediate single-row download',
    (tester) => withAppFixture(tester, (fixture) async {
      final semantics = tester.ensureSemantics();
      fixture.clipboard = '分享 https://x.com/a/status/123456';
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('从剪贴板粘贴'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('解析链接'));
      await tester.pumpAndSettle();
      expect(find.text('视频 1'), findsOneWidget);
      expect(find.text('视频 2'), findsOneWidget);
      expect(find.text('https://x.com/author/status/123456'), findsOneWidget);
      await tester.ensureVisible(find.bySemanticsLabel('下载视频 1，1280 × 720'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('下载视频 1，1280 × 720'));
      await tester.pumpAndSettle();
      expect(fixture.downloads.records, hasLength(1));
      expect(fixture.downloads.records.single.request.mediaIndex, 1);
      semantics.dispose();
    }),
  );
}
