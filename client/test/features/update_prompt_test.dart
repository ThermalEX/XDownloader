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
    'startup offers download in dialog and never installs automatically',
    (tester) => withAppFixture(tester, (f) async {
      await f.updates.setAutoCheck(true);
      f.releaseClient.respond = (_) async => availableUpdate();
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('发现新版本 2.5.0'), findsOneWidget);
      expect(find.text('不再提醒'), findsOneWidget);
      expect(f.updateBackend.calls, isEmpty);
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(f.updateBackend.calls, ['enqueue']);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('正在下载安装包'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    }),
  );
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
