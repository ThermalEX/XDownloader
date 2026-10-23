import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/features/settings/app_update_dialog.dart';
import 'package:xdownloader/features/settings/app_updates_screen.dart';

import '../support/app_fixture.dart';
import '../support/update_fixture.dart';

ReleaseCheck availableUpdate() => ReleaseCheck(
  candidate: fixtureUpdate(),
  scopeComplete: true,
  skippedReleases: 0,
  validReleases: 1,
);

Future<void> checkManually(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, '检查更新');
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'recovered ready package waits for foreground and requires installation tap',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setShowUpdatePrompt(false);
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: fixtureUpdate().candidateId,
        versionName: '2.5.0',
        phase: UpdatePhase.ready,
      );
      await f.updates.refreshTransfer();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.text('更新已下载'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('更新已下载'), findsOneWidget);
      expect(f.updateBackend.calls, isEmpty);
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: fixtureUpdate().candidateId,
        versionName: '2.5.0',
        phase: UpdatePhase.permissionRequired,
      );
      await tester.tap(find.text('继续安装'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['install:${fixtureUpdate().candidateId}']);
      expect(find.text('请允许安装本应用提供的更新，然后继续安装'), findsOneWidget);
    }),
  );
  testWidgets(
    'ready package in the open update window does not produce another prompt',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setAutoCheck(true);
      f.releaseClient.respond = (_) async => availableUpdate();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: fixtureUpdate().candidateId,
        versionName: '2.5.0',
        phase: UpdatePhase.ready,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('继续安装'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.updateBackend.calls, ['enqueue']);
    }),
  );
  testWidgets(
    'download finishing under a subpage prompts once after returning',
    (tester) => withAppFixture(tester, (f) async {
      f.releaseClient.respond = (_) async => availableUpdate();
      await f.updates.check();
      await f.updates.download();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('子页面')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: fixtureUpdate().candidateId,
        versionName: '2.5.0',
        phase: UpdatePhase.ready,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('更新已下载'), findsOneWidget);
    }),
  );
  testWidgets(
    'startup result waits for foreground and prompts exactly once on return',
    (tester) => withAppFixture(tester, (f) async {
      final pending = Completer<ReleaseCheck>();
      f.releaseClient.respond = (_) => pending.future;
      await f.updates.setAutoCheck(true);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      pending.complete(availableUpdate());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.releaseClient.checks, 1);
      expect(f.updateBackend.calls, isEmpty);
    }),
  );
  testWidgets(
    'startup prompt waits for a subpage to close',
    (tester) => withAppFixture(tester, (f) async {
      final pending = Completer<ReleaseCheck>();
      f.releaseClient.respond = (_) => pending.future;
      await f.updates.setAutoCheck(true);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('子页面')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(availableUpdate());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(f.releaseClient.checks, 1);
    }),
  );
  testWidgets(
    'startup offers download in dialog and never installs automatically',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setAutoCheck(true);
      f.releaseClient.respond = (_) async => availableUpdate();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('XDownloader 2.5.0'), findsOneWidget);
      expect(find.text('不再提醒'), findsOneWidget);
      final releasePage = tester.getRect(
        find.byKey(const Key('update_dialog_release_page')),
      );
      final row = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('update_dialog_release_page')),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(releasePage.right, closeTo(row.right, 1));
      expect(f.updateBackend.calls, isEmpty);
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['enqueue']);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('正在下载安装包'), findsOneWidget);
      expect(find.text('取消下载'), findsOneWidget);
      expect(find.text('后台继续'), findsOneWidget);
      final cancel = tester.getRect(
        find.byKey(const Key('update_dialog_cancel_download')),
      );
      final background = tester.getRect(
        find.byKey(const Key('update_dialog_dismiss')),
      );
      expect(cancel.center.dy, closeTo(background.center.dy, 1));
      expect(cancel.right, lessThanOrEqualTo(background.left));
      await tester.tap(find.text('后台继续'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.updateBackend.calls, ['enqueue']);
      expect(f.updates.transfer.phase, UpdatePhase.running);
      f.updateBackend.transfer = UpdateTransfer(
        candidateId: fixtureUpdate().candidateId,
        versionName: '2.5.0',
        phase: UpdatePhase.ready,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('更新已下载'), findsOneWidget);
      expect(f.updateBackend.calls, ['enqueue']);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('更新已下载'), findsNothing);
    }),
  );
  for (final invalidate in ['suppress', 'manual check']) {
    testWidgets(
      'deferred startup prompt respects $invalidate before returning',
      (tester) => withAppFixture(tester, (f) async {
        final pending = Completer<ReleaseCheck>();
        f.releaseClient.respond = (_) => pending.future;
        await f.updates.setAutoCheck(true);
        await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        pending.complete(availableUpdate());
        await tester.pumpAndSettle();
        if (invalidate == 'suppress') {
          await f.updates.setShowUpdatePrompt(false);
        } else {
          f.releaseClient.respond = (_) async => availableUpdate();
          await f.updates.check();
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(f.updateBackend.calls, isEmpty);
      }),
    );
  }
  testWidgets(
    'do not remind persists, keeps startup checks, and manual check overrides it',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setAutoCheck(true);
      f.releaseClient.respond = (_) async => availableUpdate();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不再提醒'));
      await tester.pumpAndSettle();
      expect((await f.store.read('updates'))['showUpdatePrompt'], false);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(f.releaseClient.checks, 2);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      expect(find.text('新版说明'), findsNothing);
      await checkManually(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('新版说明'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '不再提醒'),
            )
            .value,
        true,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('新版说明'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('启动时提醒新版'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('启动时提醒新版'));
      await tester.pumpAndSettle();
      expect((await f.store.read('updates'))['showUpdatePrompt'], true);
    }),
  );
  testWidgets(
    'manual check shows loading and errors inside the window',
    (tester) => withAppFixture(tester, (f) async {
      final pending = Completer<ReleaseCheck>();
      f.releaseClient.respond = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(home: AppUpdatesScreen(repository: f.updates)),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '检查更新');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('正在检查更新…'), findsOneWidget);
      pending.completeError(const AppFailure(FailureKind.network, '网络不可用'));
      await tester.pumpAndSettle();
      expect(find.text('网络不可用'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('网络不可用'), findsNothing);
    }),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'prompt fits narrow doubled text ${brightness.name}',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        f.releaseClient.respond = (_) async => availableUpdate();
        await f.updates.check();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AppUpdateDialog(repository: f.updates),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('不再提醒'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('不再提醒'));
        await tester.pumpAndSettle();
        expect(f.updates.preferences.showUpdatePrompt, false);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('下载更新'));
        await tester.pumpAndSettle();
        expect(f.updateBackend.calls, ['enqueue']);
        final cancel = find.byKey(const Key('update_dialog_cancel_download'));
        final background = find.byKey(const Key('update_dialog_dismiss'));
        expect(
          tester.getCenter(cancel).dy,
          closeTo(tester.getCenter(background).dy, 1),
        );
        expect(
          tester.getRect(cancel).right,
          lessThanOrEqualTo(tester.getRect(background).left),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(f.updateBackend.calls, ['enqueue', 'cancel']);
        expect(f.updates.transfer.phase, UpdatePhase.cancelled);
        expect(find.text('后台继续'), findsNothing);
        expect(find.text('关闭'), findsOneWidget);
      }),
    );
  }
  testWidgets(
    'late startup reply cannot reopen a dialog after a newer manual check',
    (tester) => withAppFixture(tester, (f) async {
      final startup = Completer<ReleaseCheck>();
      f.releaseClient.respond = (_) => f.releaseClient.checks == 1
          ? startup.future
          : Future.value(availableUpdate());
      await f.updates.setAutoCheck(true);
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AppUpdatesScreen(repository: f.updates),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await checkManually(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      startup.complete(availableUpdate());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }),
  );
  testWidgets(
    'ordinary resume does not trigger repeated automatic checks or dialogs',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setAutoCheck(true);
      f.releaseClient.respond = (_) async => availableUpdate();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(f.releaseClient.checks, 1);
      expect(find.byType(AlertDialog), findsNothing);
    }),
  );
}
