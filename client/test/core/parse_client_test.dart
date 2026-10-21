import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';

import '../support/fixture_client.dart';

const link = 'https://x.com/author/status/123456';
http.Response response(String fixture) =>
    http.Response.bytes(File('test/fixtures/$fixture').readAsBytesSync(), 200);

void main() {
  test('cancelled old response cannot become the new parse result', () async {
    final a = Completer<http.Response>(), b = Completer<http.Response>();
    final parser = ParseClient(
      clientFactory: () =>
          FixtureClient((r) => r.body.contains('123456') ? a.future : b.future),
    );
    final cancelA = ParseCancellation();
    final old = parser.parse(
      link,
      sources: [SourceCatalog.builtins.first],
      autoFallback: true,
      cancellation: cancelA,
    );
    final oldFailure = expectLater(
      old,
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      ),
    );
    final recent = parser.parse(
      'https://x.com/author/status/222222',
      sources: [SourceCatalog.builtins.first],
      autoFallback: false,
      cancellation: ParseCancellation(),
    );
    cancelA.cancel();
    b.complete(response('xdl_two.json'));
    final result = await recent;
    a.complete(response('xdl_two.json'));
    await oldFailure;
    expect(result.post.postId, '222222');
  });
  test('XDL always uses JSON POST and expands its endpoint', () async {
    final source = ParseSource(
      'custom',
      'Custom',
      'https://source.test/{id}?post={urlenc}',
      SourceKind.xdl,
      'GET',
      'ignored=body',
      false,
    );
    final parser = ParseClient(
      clientFactory: () => FixtureClient((request) {
        expect(request.method, 'POST');
        expect(request.url.path, '/123456');
        expect(request.url.queryParameters['post'], link);
        expect(jsonDecode(request.body), {'url': link});
        expect(request.headers['content-type'], contains('application/json'));
        return response('xdl_two.json');
      }),
    );
    final result = await parser.parse(
      link,
      sources: [source],
      autoFallback: false,
      cancellation: ParseCancellation(),
    );
    expect(result.author, '中文作者');
  });
  test('scrape supports configured GET and POST form', () async {
    for (final method in ['GET', 'POST']) {
      final parser = ParseClient(
        clientFactory: () => FixtureClient((request) {
          expect(request.method, method);
          expect(request.url.path, '/author');
          if (method == 'POST') {
            expect(
              request.headers['content-type'],
              contains('application/x-www-form-urlencoded'),
            );
            expect(Uri.splitQueryString(request.body), {
              'post': link,
              'id': '123456',
            });
          } else {
            expect(request.body, isEmpty);
          }
          return response('scrape_one.html');
        }),
      );
      await parser.parse(
        link,
        sources: [
          ParseSource(
            'c',
            'Custom',
            'https://source.test/{user}',
            SourceKind.scrape,
            method,
            'post={urlenc}&id={id}',
            false,
          ),
        ],
        autoFallback: true,
        cancellation: ParseCancellation(),
      );
    }
  });
  test('VX receives curl UA and source order is respected', () async {
    final seen = <String>[];
    final parser = ParseClient(
      clientFactory: () => FixtureClient((request) {
        seen.add(request.url.host);
        if (seen.length == 1) {
          expect(request.headers['user-agent'], 'curl/8.5.0');
          return http.Response('offline', 503);
        }
        return response('xdl_two.json');
      }),
    );
    final result = await parser.parse(
      link,
      sources: [SourceCatalog.builtins[3], SourceCatalog.builtins[0]],
      autoFallback: true,
      cancellation: ParseCancellation(),
    );
    expect(seen, ['api.vxtwitter.com', 'x-twitter-downloader.com']);
    expect(result.sourceId, 'xdl');
  });
  test('at most five sources and fallback off uses only current', () async {
    for (final enabled in [true, false]) {
      var calls = 0;
      final parser = ParseClient(
        clientFactory: () => FixtureClient((_) {
          calls++;
          return http.Response('offline', 500);
        }),
      );
      final sources = List.generate(
        8,
        (i) => ParseSource(
          '$i',
          '$i',
          'https://source.test/$i',
          SourceKind.scrape,
          'GET',
          '',
          false,
        ),
      );
      await expectLater(
        parser.parse(
          link,
          sources: sources,
          autoFallback: enabled,
          cancellation: ParseCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.server),
        ),
      );
      expect(calls, enabled ? 5 : 1);
    }
  });
  test('15 second source timeout and 45 second total budget', () {
    fakeAsync((async) {
      var calls = 0;
      Object? error;
      final parser = ParseClient(
        clientFactory: () => FixtureClient((_) {
          calls++;
          return Completer<http.Response>().future;
        }),
      );
      parser
          .parse(
            link,
            sources: SourceCatalog.builtins,
            autoFallback: true,
            cancellation: ParseCancellation(),
          )
          .then<void>(
            (_) => fail('must time out'),
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(seconds: 14));
      expect(calls, 1);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      async.elapse(const Duration(seconds: 15));
      expect(calls, 3);
      async.elapse(const Duration(seconds: 15));
      expect(
        error,
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.timeout),
      );
      expect(calls, 3);
    });
  });
  test('cancel stops fallback and closes only that request', () {
    fakeAsync((async) {
      final clients = <FixtureClient>[];
      Object? error;
      final parser = ParseClient(
        clientFactory: () {
          final c = FixtureClient((_) => Completer<http.Response>().future);
          clients.add(c);
          return c;
        },
      );
      final cancellation = ParseCancellation();
      parser
          .parse(
            link,
            sources: SourceCatalog.builtins,
            autoFallback: true,
            cancellation: cancellation,
          )
          .then<void>(
            (_) => fail('must cancel'),
            onError: (Object e) {
              error = e;
            },
          );
      async.flushMicrotasks();
      cancellation.cancel();
      async.flushMicrotasks();
      expect(
        error,
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      );
      expect(clients.single.closed, isTrue);
      async.elapse(const Duration(seconds: 60));
      expect(clients.length, 1);
    });
  });
  test('hung HEAD never blocks a new parse and is cancellable', () async {
    final parser = ParseClient(
      clientFactory: () => FixtureClient(
        (r) => r.method == 'HEAD'
            ? Completer<http.Response>().future
            : response('xdl_two.json'),
      ),
    );
    final cancel = ParseCancellation();
    final head = parser.probeSize(
      Uri.parse('https://video.twimg.com/a.mp4'),
      cancel,
    );
    final result = await parser.parse(
      link,
      sources: [SourceCatalog.builtins.first],
      autoFallback: false,
      cancellation: ParseCancellation(),
    );
    expect(result.items.length, 2);
    cancel.cancel();
    expect(await head, isNull);
  });
}
