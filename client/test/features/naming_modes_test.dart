import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/naming/file_naming.dart';
import 'package:xdownloader/data/storage/snapshot_schema.dart';
import 'package:xdownloader/features/home/home_controller.dart';
import 'package:xdownloader/features/settings/naming_settings_screen.dart';

import '../support/app_fixture.dart';

void main() {
  test('original titles and local date/time rules keep backwards defaults', () {
    final media = resultFor('123456');
    final variant = media.items.first.variants.first;
    final now = DateTime(2026, 10, 20, 21, 9, 7);
    expect(FileNaming.build(media, variant, useOriginalName: true), '中文视频.mp4');
    expect(
      FileNaming.build(
        media,
        variant,
        template: '{title}_{date}_{time}_{datetime}',
        now: now,
      ),
      '中文视频_2026-10-20_21-09-07_2026-10-20_21-09-07.mp4',
    );
    expect(
      FileNaming.preview('{date}_{time}', now: now),
      '2026-10-20_21-09-07.mp4',
    );
    final legacy = AppSettings.fromJson({});
    expect(legacy.useOriginalFileName, isFalse);
    final restored = AppSettings.fromJson(
      legacy.copyWith(useOriginalFileName: true).toJson(),
    );
    expect(restored.useOriginalFileName, isTrue);
    expect(restored.fileNameTemplate, FileNaming.defaultTemplate);
    expect(
      SnapshotSchema.accepts('settings', {'useOriginalFileName': 'yes'}),
      isFalse,
    );
  });

  testWidgets(
    'download honors original title selection over saved template',
    (tester) => withAppFixture(tester, (fixture) async {
      await fixture.settings.edit(
        (s) => s.copyWith(
          useOriginalFileName: true,
          fileNameTemplate: '{postId}_{date}_{time}',
        ),
      );
      final home = HomeController(fixture.dependencies);
      try {
        await home.parse('https://x.com/a/status/123456');
        await home.download(home.result!.items.first.variants.first);
        expect(
          fixture.downloads.records.single.request.displayName,
          '中文视频.mp4',
        );
      } finally {
        home.dispose();
      }
    }),
  );

  testWidgets(
    'naming choices persist and preserve the alternate rule',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名规则'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原始标题'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('filename_template')))
            .enabled,
        isFalse,
      );
      expect(find.text('示例视频.mp4'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('保存'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(NamingSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.useOriginalFileName, isTrue);
      await tester.tap(find.text('重命名规则'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义规则'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('filename_template')),
        '{title}_{date}_{time}',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(NamingSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.useOriginalFileName, isFalse);
      expect(fixture.settings.value.fileNameTemplate, '{title}_{date}_{time}');
    }),
  );

  testWidgets(
    'naming modes fit narrow screens with doubled text in both themes',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: NamingSettingsScreen(repository: fixture.settings),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('原始标题'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('保存'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(NamingSettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }),
  );
}
