import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:xdownloader/core/parsing/source_parsers.dart';
import 'package:xdownloader/core/parsing/source_exchange.dart';
import 'package:xdownloader/core/parsing/post_link.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';

import '../support/app_fixture.dart';
import '../support/fixture_client.dart';

const link = 'https://x.com/author/status/123456';
const large = 'https://video.twimg.com/amplify_video/111/vid/1080x1920/a.mp4';
const small = 'https://video.twimg.com/amplify_video/111/vid/320x568/b.mp4';
const other = 'https://video.twimg.com/ext_tw_video/222/vid/720x720/c.mp4';
ParseSource source(String id) =>
    SourceCatalog.builtins.firstWhere((s) => s.id == id);
final post = PostLink.tryParse(link)!;
String wrapper(String url, {String origin = 'https://twsaver.com/dl.php'}) =>
    '$origin?${Uri(queryParameters: {'url': url}).query}';
String row(String size, String url) =>
    '<tr><td>$size</td><td>mp4</td><td><a href="$url">download</a></td></tr>';
String table(List<String> rows) =>
    '<table><tbody>${rows.join()}</tbody></table>';
Map<String, Object?> tweetdl() => {
  'title': '测试标题',
  'thumbnail': 'https://pbs.twimg.com/a.jpg',
  'duration_seconds': 12.5,
  'formats': [
    {'preview_url': small, 'width': 9999, 'height': 9999, 'bitrate_kbps': 10},
    {'preview_url': large, 'quality': 'wrong label', 'bitrate_kbps': 100},
    {'preview_url': other},
    {'preview_url': 'https://evil.test/hidden.mp4'},
  ],
};
void main() {
  test(
    'four new sources append without changing old order or default',
    () async {
      expect(SourceCatalog.builtins.map((s) => s.id), [
        'xdl',
        'fx',
        'syndication',
        'vx',
        'twitsave',
        'snap',
        'savetwitter',
        'twdown',
        'tweetdl',
        'twsaver',
        'twmate',
      ]);
      final repo = SourceRepository(MemorySnapshotStore());
      await repo.initialize();
      expect(repo.currentId, 'xdl');
      expect(repo.list.every((s) => s.builtin), isTrue);
      repo.dispose();
    },
  );
  test('TweetDL groups CDN videos, sorts real dimensions and rejects foreign media', () {
    final r = SourceParsers.decode(
      source('tweetdl'),
      post,
      jsonEncode(tweetdl()),
    );
    expect(r.items, hasLength(2));
    expect(r.items.first.variants.map((v) => v.width), [1080, 320]);
    expect(r.items.first.variants.first.bitrate, 100000);
    expect(r.title, '测试标题');
    expect(r.thumbnail.toString(), 'https://pbs.twimg.com/a.jpg');
    expect(r.duration, const Duration(milliseconds: 12500));
  });
  test(
    'TweetDL failures and missing safe direct media cannot become success',
    () {
      for (final payload in [
        {'error': 'busy', 'formats': tweetdl()['formats']},
        {
          'formats': [
            {'preview_url': 'http://video.twimg.com/a.mp4'},
            {'download_path': '/api/proxy-download?id=1'},
          ],
        },
        {'formats': {}},
      ]) {
        expect(
          () => SourceParsers.decode(
            source('tweetdl'),
            post,
            jsonEncode(payload),
          ),
          throwsA(isA<AppFailure>()),
        );
      }
    },
  );
  test(
    'TwSaver unwraps only safe exact origin and CDN links, retaining grouping',
    () {
      final html = [
        large,
        small,
        other,
      ].map((u) => '<a href="${wrapper(u)}">mp4</a>').join();
      final r = SourceParsers.decode(source('twsaver'), post, html);
      expect(r.items, hasLength(2));
      expect(r.items.first.variants.map((v) => v.width), [1080, 320]);
    },
  );
  test(
    'TwSaver rejects misleading hosts, paths, schemes, ports and user info',
    () {
      final bad = [
        wrapper('https://video.twimg.com.evil.test/a.mp4'),
        wrapper('https://name@video.twimg.com/a.mp4'),
        wrapper('https://video.twimg.com:444/a.mp4'),
        wrapper('http://video.twimg.com/a.mp4'),
        wrapper(large, origin: 'https://twsaver.com.evil.test/dl.php'),
        wrapper(large, origin: 'http://twsaver.com/dl.php'),
        wrapper(large, origin: 'https://name@twsaver.com/dl.php'),
        wrapper(large, origin: 'https://twsaver.com/other.php'),
      ];
      for (final u in bad) {
        expect(
          () => SourceParsers.decode(
            source('twsaver'),
            post,
            '<a href="$u">mp4</a>',
          ),
          throwsA(isA<AppFailure>()),
          reason: u,
        );
      }
    },
  );
  test('TWMate groups each video table and ignores foreign or dimensionless rows', () {
    final html =
        '<h4>测试 &amp; 标题</h4><img src="https://pbs.twimg.com/a.jpg">${table([row('320x568', 'https://twmate.com/download/low.mp4?iu=one'), row('1080x1920', 'https://twmate.com/download/high.mp4?iu=two'), row('1080x1920', 'https://evil.test/download/no.mp4'), row('unknown', 'https://twmate.com/download/no.mp4')])}${table([row('720x720', 'https://twmate.com/download/other.mp4?iu=three')])}';
    final r = SourceParsers.decode(source('twmate'), post, html);
    expect(r.items, hasLength(2));
    expect(r.items.first.variants.map((v) => v.width), [1080, 320]);
    expect(r.title, '测试 & 标题');
    expect(r.thumbnail.toString(), 'https://pbs.twimg.com/a.jpg');
  });
  test('TWMate malformed or non-HTTPS proxy replies fail', () {
    for (final html in [
      table([row('720x720', 'http://twmate.com/download/a.mp4')]),
      table([row('720x720', 'https://twmate.com.evil.test/download/a.mp4')]),
      '<a href="https://twmate.com/download/a.mp4">MP4</a>',
    ]) {
      expect(
        () => SourceParsers.decode(source('twmate'), post, html),
        throwsA(isA<AppFailure>()),
      );
    }
  });
  test('new fixed POST protocols survive export and persistence', () async {
    final store = MemorySnapshotStore();
    final repo = SourceRepository(store);
    await repo.initialize();
    for (final id in ['tweetdl', 'twmate']) {
      final s = source(id);
      final raw = {
        ...s.toJson(),
        'id': 'custom_$id',
        'endpoint': 'https://custom.test/$id',
        'method': 'GET',
      };
      final packet = jsonEncode({
        'format': 'xdownloader.sources',
        'version': 1,
        'sources': [raw],
      });
      final imported = SourceExchange.decode(packet).single;
      expect(imported.method, 'POST');
      await repo.addCustom(ParseSource.fromJson(raw));
      expect(repo.list.last.method, 'POST');
    }
    final restored = SourceRepository(store);
    await restored.initialize();
    expect(restored.list.where((s) => !s.builtin).map((s) => s.method), [
      'POST',
      'POST',
    ]);
    repo.dispose();
    restored.dispose();
  });
  test('all four network requests use the expected URL and body', () async {
    for (final id in ['twdown', 'tweetdl', 'twsaver', 'twmate']) {
      final s = source(id);
      final parser = ParseClient(
        clientFactory: () => FixtureClient((req) {
          expect(req.url.host, Uri.parse(s.endpoint).host);
          if (id == 'tweetdl') {
            expect(req.method, 'POST');
            expect(req.headers['content-type'], contains('application/json'));
            expect(jsonDecode(req.body), {'url': link});
            return http.Response.bytes(utf8.encode(jsonEncode(tweetdl())), 200);
          }
          if (id == 'twsaver') {
            expect(req.method, 'GET');
            expect(req.url.queryParameters['url'], link);
            return http.Response('<a href="${wrapper(large)}">MP4</a>', 200);
          }
          expect(req.method, 'POST');
          expect(
            req.headers['content-type'],
            contains('application/x-www-form-urlencoded'),
          );
          expect(
            Uri.splitQueryString(req.body),
            id == 'twdown'
                ? {'URL': link}
                : {'page': link, 'ftype': 'all', 'ajax': '1'},
          );
          return http.Response(
            id == 'twdown'
                ? '<a href="$large">MP4</a>'
                : table([
                    row('1080x1920', 'https://twmate.com/download/a.mp4?iu=ok'),
                  ]),
            200,
          );
        }),
      );
      final r = await parser.parse(
        link,
        sources: [s],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      expect(r.items.first.variants.first.width, 1080);
    }
  });
}
