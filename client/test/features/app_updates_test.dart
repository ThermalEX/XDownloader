import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/features/settings/app_updates_screen.dart';

import '../support/app_fixture.dart';
import '../support/update_fixture.dart';

ReleaseCheck updateCheck(UpdateChannel channel) => ReleaseCheck(
  candidate: fixtureUpdate(channel: channel),
  scopeComplete: true,
  skippedReleases: 0,
  validReleases: 1,
);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pending target version stays explicit when a newer release is found',
    (tester) => withAppFixture(tester, (f) async {
      f.updateBackend.transfer = const UpdateTransfer(
        candidateId: 'old-ready',
        phase: UpdatePhase.ready,
        versionName: '2.5.0',
        versionCode: 15,
      );
      await f.updates.refreshTransfer();
      f.releaseClient.respond = (_) async => ReleaseCheck(
        candidate: fixtureUpdate(code: 16, channel: UpdateChannel.beta),
        scopeComplete: true,
        skippedReleases: 0,
        validReleases: 1,
      );
      await f.updates.check();
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('待安装版本：2.5.0'));
      expect(find.text('待安装版本：2.5.0'), findsOneWidget);
      await reveal(tester, find.text('继续安装'));
      await tester.tap(find.text('继续安装'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['install:old-ready']);
    }),
  );
  testWidgets(
    'settings opens update page with named channels and verified download controls',
    (tester) => withAppFixture(tester, (f) async {
      f.releaseClient.respond = (c) async => updateCheck(c);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('settings_updates')));
      await tester.tap(find.byKey(const Key('settings_updates')));
      await tester.pumpAndSettle();
      expect(find.text('稳定版'), findsOneWidget);
      expect(find.text('Beta 版'), findsOneWidget);
      expect(find.text('2.4.1'), findsOneWidget);
      await reveal(tester, find.text('检查更新'));
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('新版说明'), findsOneWidget);
      await reveal(tester, find.text('下载更新'));
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['enqueue']);
      await reveal(tester, find.byKey(const Key('update_channel_beta')));
      await tester.tap(find.byKey(const Key('update_channel_beta')));
      await tester.pumpAndSettle();
      expect(find.text('取消下载并切换渠道？'), findsOneWidget);
      await tester.tap(find.text('继续当前下载'));
      await tester.pumpAndSettle();
      expect(f.updates.preferences.channel, UpdateChannel.stable);
      await tester.tap(find.byKey(const Key('update_channel_beta')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消并切换'));
      await tester.pumpAndSettle();
      expect(f.updates.preferences.channel, UpdateChannel.beta);
      expect(f.updateBackend.calls, ['enqueue', 'cancel']);
    }),
  );
  testWidgets(
    'restored ready update can install and browser fallback opens release page',
    (tester) => withAppFixture(tester, (f) async {
      final update = fixtureUpdate();
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: update.candidateId,
        phase: UpdatePhase.ready,
        bytes: 80,
        totalBytes: 80,
      );
      await f.updates.refreshTransfer();
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('继续安装'));
      await tester.tap(find.text('继续安装'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['install:${update.candidateId}']);
      await reveal(tester, find.text('前往发布页下载'));
      await tester.tap(find.text('前往发布页下载'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.pages.single.host, 'github.com');
    }),
  );
  testWidgets(
    'empty incomplete and current results have distinct messages',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      for (final sample in [
        (
          const ReleaseCheck(
            scopeComplete: true,
            skippedReleases: 0,
            validReleases: 0,
          ),
          '暂未找到可用的更新发布',
        ),
        (
          const ReleaseCheck(
            scopeComplete: false,
            skippedReleases: 1,
            validReleases: 0,
          ),
          '部分发布未能验证，请稍后重试或查看发布页',
        ),
        (
          const ReleaseCheck(
            scopeComplete: true,
            skippedReleases: 0,
            validReleases: 1,
          ),
          '当前渠道没有更高版本',
        ),
      ]) {
        f.releaseClient.respond = (_) async => sample.$1;
        await f.updates.check();
        await tester.pumpAndSettle();
        expect(find.text(sample.$2), findsOneWidget);
      }
    }),
  );
  testWidgets(
    'startup check never blocks explicit share or opens an installer',
    (tester) => withAppFixture(tester, (f) async {
      final pending = Completer<ReleaseCheck>();
      f.releaseClient.respond = (_) => pending.future;
      await f.updates.setAutoCheck(true);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      f.shareEvents.add('https://x.com/author/status/123456');
      await tester.pumpAndSettle();
      expect(f.parser.calls, contains('https://x.com/author/status/123456'));
      pending.complete(updateCheck(UpdateChannel.stable));
      await tester.pumpAndSettle();
      expect(find.byTooltip('发现新版本'), findsOneWidget);
      expect(f.updateBackend.calls, isEmpty);
    }),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'update page supports narrow large text ${brightness.name}',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: brightness,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AppUpdatesScreen(repository: f.updates),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }),
    );
  }
}
