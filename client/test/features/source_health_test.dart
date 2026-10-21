import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:xdownloader/features/settings/source_health_controller.dart';
import 'package:xdownloader/features/settings/sources_screen.dart';

import '../support/app_fixture.dart';

void main() {
  test('all checks use only their own source, bound concurrency and cancel on disposal', () async {
    final parser = _PendingParser();
    final health = SourceHealthController(parser);
    final checking = health.checkAll(SourceCatalog.builtins);
    expect(parser.cancellations, hasLength(3));
    health.dispose();
    expect(parser.cancellations.every((c) => c.isCancelled), isTrue);
    for (final result in parser.results) {
      result.complete(resultFor('123456'));
    }
    await checking;
    expect(parser.results, hasLength(3));
  });
  testWidgets(
    'source check results fit 320dp with doubled text',
    (tester) => withAppFixture(tester, (fixture) async {
      tester.view.physicalSize = const Size(320, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SourcesScreen(
            repository: fixture.sources,
            parser: fixture.parser,
          ),
        ),
      );
      await tester.tap(find.text('检测全部'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fixture.parser.calls, hasLength(fixture.sources.list.length));
    }),
  );
  testWidgets(
    'individual and all-source health checks show results without selecting a source',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(
            repository: fixture.sources,
            parser: fixture.parser,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('检测 FxTwitter'));
      await tester.pumpAndSettle();
      expect(fixture.parser.calls, hasLength(1));
      expect(fixture.sources.currentId, 'xdl');
      expect(find.textContaining('可用'), findsWidgets);
      expect(find.textContaining('1280 × 720'), findsWidgets);
      await tester.tap(find.text('检测全部'));
      await tester.pumpAndSettle();
      expect(fixture.parser.calls, hasLength(fixture.sources.list.length + 1));
      expect(fixture.sources.currentId, 'xdl');
    }),
  );
  testWidgets(
    'health error is visible and leaving cancels pending checks safely',
    (tester) => withAppFixture(tester, (fixture) async {
      fixture.parser.respond = (_, _) async =>
          throw const AppFailure(FailureKind.server, '测试源不可用');
      await tester.pumpWidget(
        MaterialApp(
          home: SourcesScreen(
            repository: fixture.sources,
            parser: fixture.parser,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('检测 FxTwitter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('测试源不可用'), findsOneWidget);
      final pending = Completer<MediaResult>();
      fixture.parser.respond = (_, _) => pending.future;
      await tester.tap(find.byTooltip('检测 FxTwitter'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(resultFor('123456'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }),
  );
}

class _PendingParser extends ParseClient {
  final cancellations = <ParseCancellation>[];
  final results = <Completer<MediaResult>>[];
  @override
  Future<MediaResult> parse(
    String input, {
    required List<ParseSource> sources,
    required bool autoFallback,
    required ParseCancellation cancellation,
  }) {
    expect(sources, hasLength(1));
    expect(autoFallback, isFalse);
    cancellations.add(cancellation);
    final result = Completer<MediaResult>();
    results.add(result);
    return result.future;
  }
}
