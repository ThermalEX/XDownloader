import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/request_rotation.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/fixture_client.dart';

const link = 'https://x.com/a/status/123456';
const html =
    '<a href="https://video.twimg.com/amplify_video/1/vid/320x568/a.mp4">MP4</a>';
const source = ParseSource(
  'a',
  'A',
  'https://source.test/a',
  SourceKind.scrape,
  'GET',
  '',
  false,
);
const countOne = RequestRotation(RotationMode.count, 1);

void main() {
  late Directory temp;
  late SnapshotStore store;
  late SourceRepository repository;
  late DateTime now;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-rotation-');
    store = SnapshotStore(temp);
    now = DateTime.utc(2026, 10, 28);
    repository = SourceRepository(store, now: () => now);
    await repository.initialize();
  });
  tearDown(() async {
    repository.dispose();
    await temp.delete(recursive: true);
  });

  for (final kind in [SourceKind.scrape, SourceKind.snap]) {
    for (final status in [429, 503]) {
      test(
        '$kind $status records cooldown before a broken response body',
        () async {
          final selected = kind == SourceKind.snap
              ? SourceCatalog.builtins.firstWhere((s) => s.kind == kind)
              : source;
          var calls = 0;
          final parser = ParseClient(
            requestProfiles: repository.requestProfiles,
            clientFactory: () => _RawClient((_) {
              calls++;
              return http.StreamedResponse(
                Stream.error(http.ClientException('body reset')),
                status,
                headers: {'retry-after': '600'},
              );
            }),
          );
          Future<void> parse() => parser.parse(
            link,
            sources: [selected],
            autoFallback: false,
            cancellation: ParseCancellation(),
          );
          await expectLater(parse(), throwsA(isA<AppFailure>()));
          expect(
            repository.requestProfiles.cooldownRemaining(selected.id),
            const Duration(minutes: 10),
          );
          await expectLater(parse(), throwsA(isA<AppFailure>()));
          expect(calls, 1);
        },
      );
    }
  }

  test('overlapping parses capture one configuration and late completion cannot advance the new one', () async {
    repository.requestProfiles.configure({
      'a': const RequestRotation(RotationMode.count, 2),
    });
    final pending = List.generate(3, (_) => Completer<http.Response>());
    final headers = <String?>[];
    final parser = ParseClient(
      requestProfiles: repository.requestProfiles,
      clientFactory: () => FixtureClient((request) {
        headers.add(request.headers['user-agent']);
        return headers.length <= 3
            ? pending[headers.length - 1].future
            : http.Response(html, 200);
      }),
    );
    Future<void> parse() => parser.parse(
      link,
      sources: [source],
      autoFallback: false,
      cancellation: ParseCancellation(),
    );
    final first = parse(), second = parse(), third = parse();
    pending[0].complete(http.Response(html, 200));
    pending[1].complete(http.Response(html, 200));
    await Future.wait([first, second]);
    await parse();
    pending[2].complete(http.Response(html, 200));
    await third;
    await parse();
    expect(headers.take(3).toSet(), hasLength(1));
    expect(headers[3], isNot(headers[0]));
    expect(headers[4], headers[3]);
  });

  test(
    'editing a custom source into VX clears its unsupported policy durably',
    () async {
      await repository.addCustom(source);
      await repository.setRotation('a', countOne);
      await repository.addCustom(
        const ParseSource(
          'a',
          'A',
          'https://source.test/a',
          SourceKind.vx,
          'GET',
          '',
          false,
        ),
      );
      expect(repository.rotationFor('a').mode, RotationMode.off);
      final restored = SourceRepository(store);
      await restored.initialize();
      expect(restored.rotationFor('a').mode, RotationMode.off);
      restored.dispose();
    },
  );

  test(
    'policies persist through other source edits and restore independently',
    () async {
      await repository.setRotation('xdl', countOne);
      await repository.setRotation(
        'snap',
        const RequestRotation(RotationMode.minutes, 5),
      );
      await repository.select('snap');
      await repository.setFallback(false);
      final restored = SourceRepository(store);
      await restored.initialize();
      expect(restored.rotationFor('xdl').mode, RotationMode.count);
      expect(restored.rotationFor('snap').interval, 5);
      expect(restored.rotationFor('fx').mode, RotationMode.off);
      expect(restored.currentId, 'snap');
      expect(restored.autoFallback, isFalse);
      restored.dispose();
      await expectLater(
        repository.setRotation('vx', countOne),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        repository.setRotation('missing', countOne),
        throwsA(isA<AppFailure>()),
      );
    },
  );

  test(
    'failed policy writes leave visible and active policy unchanged',
    () async {
      await repository.setRotation('xdl', countOne);
      final capture = repository.requestProfiles.begin('xdl');
      await Directory('${temp.path}/sources.json.tmp').create();
      await expectLater(
        repository.setRotation('xdl', const RequestRotation()),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.rotationFor('xdl').mode, RotationMode.count);
      expect(repository.requestProfiles.begin('xdl').headers, capture.headers);
    },
  );

  test('invalid policy snapshot recovers last valid backup', () async {
    await repository.setRotation('xdl', countOne);
    await repository.select('fx');
    await File('${temp.path}/sources.json').writeAsString(
      jsonEncode({
        'version': 1,
        'data': {
          'rotation': {
            'xdl': {'mode': 'count', 'interval': 0},
          },
        },
      }),
    );
    final restored = SourceRepository(store);
    await restored.initialize();
    expect(restored.rotationFor('xdl').interval, 1);
    restored.dispose();
  });

  test('completed attempts rotate wire headers but retain protocol and VX identity', () async {
    repository.requestProfiles.configure({'a': countOne, 'vx': countOne});
    final headers = <Map<String, String>>[];
    final parser = ParseClient(
      requestProfiles: repository.requestProfiles,
      clientFactory: () => FixtureClient((r) {
        headers.add(Map.of(r.headers));
        return http.Response(html, 200);
      }),
    );
    for (var i = 0; i < 2; i++) {
      await parser.parse(
        link,
        sources: [source],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
    }
    expect(headers[0]['user-agent'], isNot(headers[1]['user-agent']));
    expect(headers[0]['accept-language'], isNotNull);
    expect(headers[0]['referer'], 'https://x.com/');
    expect(headers[0]['accept'], contains('application/json'));
    await expectLater(
      parser.parse(
        link,
        sources: [SourceCatalog.builtins[3]],
        autoFallback: false,
        cancellation: ParseCancellation(),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(headers.last['user-agent'], 'curl/8.5.0');
    expect(headers.last['accept-language'], isNull);
  });

  test(
    'token bootstrap and submit keep captured headers across policy edits',
    () async {
      await repository.setRotation('snap', countOne);
      final seen = <Map<String, String>>[];
      final parser = ParseClient(
        requestProfiles: repository.requestProfiles,
        clientFactory: () => FixtureClient((r) async {
          seen.add(Map.of(r.headers));
          if (r.method == 'GET') {
            await repository.setRotation('snap', const RequestRotation());
            return http.Response('<input name="token" value="abc">', 200);
          }
          expect(Uri.splitQueryString(r.body)['token'], 'abc');
          return http.Response(jsonEncode({'error': false, 'data': html}), 200);
        }),
      );
      await parser.parse(
        link,
        sources: [SourceCatalog.builtins.firstWhere((s) => s.id == 'snap')],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      expect(seen, hasLength(2));
      expect(seen[0]['user-agent'], seen[1]['user-agent']);
      expect(seen[0]['accept-language'], seen[1]['accept-language']);
    },
  );

  test('cancelled attempt does not count toward the next rotation', () async {
    repository.requestProfiles.configure({'a': countOne});
    final first = repository.requestProfiles.begin('a').headers;
    final pending = Completer<http.Response>();
    var calls = 0;
    final parser = ParseClient(
      requestProfiles: repository.requestProfiles,
      clientFactory: () => FixtureClient((r) {
        expect(r.headers['user-agent'], first['user-agent']);
        return ++calls == 1 ? pending.future : http.Response(html, 200);
      }),
    );
    final cancellation = ParseCancellation();
    final parsing = parser.parse(
      link,
      sources: [source],
      autoFallback: false,
      cancellation: cancellation,
    );
    final failure = expectLater(parsing, throwsA(isA<AppFailure>()));
    cancellation.cancel();
    await failure;
    pending.complete(http.Response('', 429, headers: {'retry-after': '600'}));
    await Future<void>.delayed(Duration.zero);
    await parser.parse(
      link,
      sources: [source],
      autoFallback: false,
      cancellation: ParseCancellation(),
    );
    expect(calls, 2);
  });

  test('429 cools selected source, falls back once, and does not bypass disabled fallback', () async {
    final calls = <String>[];
    final parser = ParseClient(
      requestProfiles: repository.requestProfiles,
      clientFactory: () => FixtureClient((r) {
        calls.add(r.url.path);
        return r.url.path == '/a'
            ? http.Response('', 429, headers: {'retry-after': '60'})
            : http.Response(html, 200);
      }),
    );
    const backup = ParseSource(
      'b',
      'B',
      'https://source.test/b',
      SourceKind.scrape,
      'GET',
      '',
      false,
    );
    Future<void> parse(bool fallback) async {
      await parser.parse(
        link,
        sources: [source, backup],
        autoFallback: fallback,
        cancellation: ParseCancellation(),
      );
    }

    await parse(true);
    expect(calls, ['/a', '/b']);
    await expectLater(
      parse(false),
      throwsA(
        isA<AppFailure>().having((e) => e.message, 'message', contains('冷却')),
      ),
    );
    expect(calls, hasLength(2));
    await parse(true);
    expect(calls, ['/a', '/b', '/b']);
    now = now.add(const Duration(seconds: 60));
    await parse(true);
    expect(calls, ['/a', '/b', '/b', '/a', '/b']);
  });

  test(
    'bootstrap 429 stops submit and preserves cooldown after source selection',
    () async {
      final calls = <String>[];
      final parser = ParseClient(
        requestProfiles: repository.requestProfiles,
        clientFactory: () => FixtureClient((r) {
          calls.add(r.method);
          return http.Response('', 429);
        }),
      );
      final snap = SourceCatalog.builtins.firstWhere((s) => s.id == 'snap');
      Future<void> parse() => parser.parse(
        link,
        sources: [snap],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      await expectLater(parse(), throwsA(isA<AppFailure>()));
      await repository.select('snap');
      await expectLater(parse(), throwsA(isA<AppFailure>()));
      expect(calls, ['GET']);
    },
  );
}

class _RawClient extends http.BaseClient {
  _RawClient(this.respond);
  final http.StreamedResponse Function(http.BaseRequest) respond;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      respond(request);
}
