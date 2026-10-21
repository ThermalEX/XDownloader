import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/post_link.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:xdownloader/core/parsing/source_parsers.dart';

import '../support/fixture_client.dart';

void main() {
  const link = 'https://x.com/author/status/123456';
  const snap = ParseSource(
    'snap',
    'SnapTwitter',
    'https://snaptwitter.com/action.php',
    SourceKind.snap,
    'POST',
    '',
    true,
  );
  final post = PostLink.tryParse(link)!;
  const small =
      'https://video.twimg.com/amplify_video/123456/vid/320x568/a.mp4';
  const large =
      'https://video.twimg.com/amplify_video/123456/vid/1080x1920/b.mp4';
  String wrapper(String url) =>
      'https://dl.snapcdn.app/get?token=e30.${base64Url.encode(utf8.encode(jsonEncode({'url': url}))).replaceAll('=', '')}.sig';
  test(
    'SnapTwitter fetches normal form token then posts within one parse attempt',
    () async {
      final requests = <http.Request>[];
      final parser = ParseClient(
        clientFactory: () => FixtureClient((r) {
          requests.add(r);
          if (r.method == 'GET') {
            expect(r.url.path, '/en2');
            return http.Response(
              '<input value="a+b&amp;c" name="token" type="hidden">',
              200,
            );
          }
          expect(Uri.splitQueryString(r.body), {'url': link, 'token': 'a+b&c'});
          return http.Response(
            jsonEncode({'error': false, 'data': '<a href="$large">MP4</a>'}),
            200,
          );
        }),
      );
      final result = await parser.parse(
        link,
        sources: [snap],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(result.items.single.variants.single.width, 1080);
    },
  );
  test('cancelled or timed out form lookup never sends a later POST', () async {
    final pending = Completer<http.Response>();
    final methods = <String>[];
    final parser = ParseClient(
      clientFactory: () => FixtureClient((r) {
        methods.add(r.method);
        return pending.future;
      }),
    );
    final cancel = ParseCancellation();
    final future = parser.parse(
      link,
      sources: [snap],
      autoFallback: false,
      cancellation: cancel,
    );
    final failure = expectLater(
      future,
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    pending.complete(http.Response('<input name="token" value="abc">', 200));
    await failure;
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['GET']);
    fakeAsync((async) {
      final late = Completer<http.Response>();
      final calls = <String>[];
      final p = ParseClient(
        clientFactory: () => FixtureClient((r) {
          calls.add(r.method);
          return late.future;
        }),
      );
      AppFailure? error;
      p
          .parse(
            link,
            sources: [snap],
            autoFallback: false,
            cancellation: ParseCancellation(),
          )
          .then<void>(
            (_) => fail('timeout expected'),
            onError: (Object e) {
              error = e as AppFailure;
            },
          );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 16));
      async.flushMicrotasks();
      expect(error?.kind, FailureKind.timeout);
      late.complete(http.Response('<input name="token" value="abc">', 200));
      async.flushMicrotasks();
      expect(calls, ['GET']);
    });
  });
  test('signed source metadata returns all safe Twitter MP4 variants only', () {
    final source = SourceCatalog.builtins.firstWhere(
      (s) => s.id == 'savetwitter',
    );
    final html =
        '<h3>公开样例</h3><a href="${wrapper(large)}">HD</a><a href="${wrapper(small)}">LOW</a><a href="${wrapper('https://video.twimg.com.evil.test/a.mp4')}">bad</a><a href="${wrapper('http://video.twimg.com/a.mp4')}">bad</a>';
    final result = SourceParsers.decode(
      source,
      post,
      jsonEncode({'status': 'ok', 'data': html}),
    );
    expect(result.items.single.variants.map((v) => v.width), [1080, 320]);
    expect(result.title, '公开样例');
    expect(
      () => SourceParsers.decode(
        source,
        post,
        jsonEncode({'status': 'verify', 'data': '<a href="$large">MP4</a>'}),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => SourceParsers.decode(
        snap,
        post,
        jsonEncode({'error': true, 'data': '<a href="$large">MP4</a>'}),
      ),
      throwsA(isA<AppFailure>()),
    );
  });
}
