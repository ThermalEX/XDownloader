import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/features/settings/about_screen.dart';
import 'package:xdownloader/features/settings/app_update_dialog.dart';
import 'package:xdownloader/features/settings/release_notes.dart';

import '../support/app_fixture.dart';
import '../support/update_fixture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'release Markdown renders readable content at 320dp 2x $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opened = <Uri>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReleaseNotes(
                  data: '# 版本标题\n\n## 主要更新\n\n- **收藏**支持批量操作\n- `规则`支持拖动\n\n[发布记录](https://github.com/ThermalEX/XDownloader/releases)\n\n![图片](https://example.invalid/image.png)',
                  onOpenLink: (uri) async {
                    opened.add(uri);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final plain = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '')
            .join('\n');
        expect(plain, contains('版本标题'));
        expect(plain, contains('主要更新'));
        expect(plain, contains('收藏支持批量操作'));
        expect(plain, isNot(contains('# 版本标题')));
        expect(plain, isNot(contains('**收藏**')));
        expect(find.byType(Image), findsNothing);
        final link = find.text('发布记录', findRichText: true);
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        expect(opened.single.host, 'github.com');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'about opens bundled changelog offline',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('changelog_entry')),
        200,
      );
      await tester.tap(find.byKey(const Key('changelog_entry')));
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.byType(ReleaseNotes), findsOneWidget);
      expect(
        find.text('XDownloader 2.11.0', findRichText: true),
        findsOneWidget,
      );
      expect(f.releaseClient.checks, 0);
      expect(tester.takeException(), isNull);
    }),
  );
  testWidgets(
    'update dialog shares the Markdown renderer',
    (tester) => withAppFixture(tester, (f) async {
      f.releaseClient.respond = (_) async => ReleaseCheck(
        candidate: fixtureUpdate(),
        scopeComplete: true,
        skippedReleases: 0,
        validReleases: 1,
      );
      await f.updates.check();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppUpdateDialog(repository: f.updates)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseNotes), findsOneWidget);
      expect(find.text('新版说明', findRichText: true), findsOneWidget);
    }),
  );
}
