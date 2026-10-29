import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/request_rotation.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/features/settings/request_rotation_dialog.dart';
import 'package:xdownloader/features/settings/sources_screen.dart';

import '../support/app_fixture.dart';

void main() {
  testWidgets(
    'pending save cannot dismiss and failed save stays retryable without changing policy',
    (tester) async {
      final store = _ControlledStore();
      final repository = SourceRepository(store);
      await repository.initialize();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => RequestRotationDialog(
                    source: repository.list.first,
                    repository: repository,
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<RotationMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按解析次数').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '3');
      store.pending = Completer<void>();
      store.fail = true;
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('正在保存…'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.byType(RequestRotationDialog), findsOneWidget);
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('无法保存测试配置'), findsOneWidget);
      expect(repository.rotationFor('xdl').mode, RotationMode.off);
      store.pending = null;
      store.fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(RequestRotationDialog), findsNothing);
      expect(repository.rotationFor('xdl').interval, 3);
    },
  );
  testWidgets(
    'source menu opens rotation settings and saves validated count',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(
            repository: fixture.sources,
            parser: fixture.parser,
          ),
        ),
      );
      await tester.tap(find.byTooltip('${fixture.sources.list.first.name} 操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('请求配置轮换'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<RotationMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按解析次数').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1000 的整数'), findsOneWidget);
      expect(fixture.sources.rotationFor('xdl').mode, RotationMode.off);
      await tester.enterText(find.byType(TextFormField), '3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(RequestRotationDialog), findsNothing);
      expect(fixture.sources.rotationFor('xdl').mode, RotationMode.count);
      expect(fixture.sources.rotationFor('xdl').interval, 3);
      expect(find.text('请求轮换 · 每 3 次解析'), findsOneWidget);
    }),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'rotation form scrolls at 320dp with doubled text in ${brightness.name}',
      (tester) => withAppFixture(tester, (fixture) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fixture.sources.setRotation(
          'xdl',
          const RequestRotation(RotationMode.minutes, 5),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => RequestRotationDialog(
                      source: fixture.sources.list.first,
                      repository: fixture.sources,
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TextFormField));
        await tester.enterText(find.byType(TextFormField), '1441');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 1–1440 的整数'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(fixture.sources.rotationFor('xdl').interval, 5);
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
