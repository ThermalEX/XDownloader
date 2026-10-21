import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/features/settings/sources_screen.dart';

import '../support/app_fixture.dart';

String packet() => jsonEncode({
  'format': 'xdownloader.sources',
  'version': 1,
  'sources': [
    const ParseSource(
      '',
      '共享测试源',
      'https://example.test/?url={urlenc}',
      SourceKind.scrape,
      'GET',
      '',
      false,
    ).toJson(),
  ],
});

void main() {
  testWidgets(
    'clipboard import and export preserve custom source definitions',
    (tester) => withAppFixture(tester, (fixture) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(
            repository: fixture.sources,
            readClipboard: () async => packet(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('源导入与导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入'));
      await tester.pumpAndSettle();
      expect(fixture.sources.list.last.name, '共享测试源');
      await tester.tap(find.byTooltip('源导入与导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出到剪贴板'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied!)['sources'].last['name'], '共享测试源');
    }),
  );
  testWidgets(
    'leaving during clipboard read cancels stale import',
    (tester) => withAppFixture(tester, (fixture) async {
      final pending = Completer<String?>();
      final count = fixture.sources.list.length;
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(
            repository: fixture.sources,
            readClipboard: () => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('源导入与导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(packet());
      await tester.pumpAndSettle();
      expect(fixture.sources.list.length, count);
      expect(tester.takeException(), isNull);
    }),
  );
}
