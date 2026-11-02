import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/request_rotation.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/features/settings/risk_protection_screen.dart';
import 'package:xdownloader/features/settings/rule_settings_screen.dart';
import 'package:xdownloader/features/settings/sources_screen.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'rules open one global protection page with direct radio choices',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: RuleSettingsScreen(dependencies: f.dependencies)),
      );
      await tester.tap(find.text('风控保护'));
      await tester.pumpAndSettle();
      expect(find.byType(RiskProtectionScreen), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<RotationMode>), findsNothing);
      await tester.tap(find.text('按解析次数'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('轮换间隔'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1000 的整数'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(f.sources.requestProtection.interval, 3);
      for (final id in ['xdl', 'fx', 'snap', 'twmate']) {
        expect(f.sources.requestProfiles.begin(id).headers, isNotEmpty);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('每 3 次解析'), findsOneWidget);
    }),
  );

  testWidgets(
    'source menus no longer contain individual protection settings',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(repository: f.sources, parser: f.parser),
        ),
      );
      await tester.tap(find.byTooltip('${f.sources.list.first.name} 操作'));
      await tester.pumpAndSettle();
      expect(find.text('请求配置轮换'), findsNothing);
      expect(find.text('提高优先级'), findsOneWidget);
      expect(find.text('导出此源'), findsOneWidget);
    }),
  );

  testWidgets(
    'failed global save stays off and is retryable after pending operation',
    (tester) async {
      final store = _ControlledStore();
      final repository = SourceRepository(store);
      await repository.initialize();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(home: RiskProtectionScreen(repository: repository)),
      );
      store.pending = Completer<void>();
      store.fail = true;
      await tester.tap(find.text('按时间'));
      await tester.pump();
      expect(repository.requestProtection.mode, RotationMode.off);
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('无法保存测试配置'), findsOneWidget);
      expect(repository.requestProtection.mode, RotationMode.off);
      store.pending = null;
      store.fail = false;
      await tester.tap(find.text('按时间'));
      await tester.pumpAndSettle();
      expect(repository.requestProtection.mode, RotationMode.minutes);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'protection settings fit 320dp doubled text ${brightness.name}',
      (tester) => withAppFixture(tester, (f) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await f.sources.setRequestProtection(
          const RequestRotation(RotationMode.minutes, 5),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RiskProtectionScreen(repository: f.sources),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('轮换间隔'), 200);
        await tester.tap(find.text('轮换间隔'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '1441');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 1–1440 的整数'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(f.sources.requestProtection.interval, 5);
      }),
    );
  }
}

class _ControlledStore extends MemorySnapshotStore {
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    await pending?.future;
    if (fail) throw const AppFailure(FailureKind.storage, '无法保存测试配置');
    await super.write(key, data);
  }
}
