import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media.dart';
import '../models/source.dart';
import '../models/app_failure.dart';
import 'post_link.dart';
import 'source_parsers.dart';

class ParseCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class ParseClient {
  ParseClient({http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() clientFactory;
  static void validateSource(ParseSource source) {
    _request(
      source,
      PostLink('123456', 'i', Uri.parse('https://x.com/i/status/123456')),
    );
  }

  Future<MediaResult> parse(
    String input, {
    required List<ParseSource> sources,
    required bool autoFallback,
    required ParseCancellation cancellation,
  }) async {
    final post = PostLink.tryParse(input);
    if (post == null) {
      throw const AppFailure(FailureKind.invalidLink, '请输入有效的 X 帖子链接');
    }
    final deadline = Completer<void>();
    final timer = Timer(const Duration(seconds: 45), deadline.complete);
    AppFailure last = const AppFailure(FailureKind.server, '没有可用的解析源');
    try {
      for (final source in sources.take(autoFallback ? 5 : 1)) {
        _checkCancelled(cancellation);
        if (deadline.isCompleted) {
          throw const AppFailure(FailureKind.timeout, '解析超时，请重试');
        }
        final client = clientFactory();
        var active = true;
        try {
          final response = await Future.any<http.Response>([
            _fetch(
              client,
              source,
              post,
              cancellation,
              () => active,
            ).timeout(const Duration(seconds: 15)),
            cancellation.whenCancelled.then(
              (_) => throw const AppFailure(FailureKind.cancelled, '已取消解析'),
            ),
            deadline.future.then(
              (_) => throw const AppFailure(FailureKind.timeout, '解析超时，请重试'),
            ),
          ]);
          _checkCancelled(cancellation);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw AppFailure(
              response.statusCode == 404
                  ? FailureKind.noVideo
                  : FailureKind.server,
              '解析源暂时不可用',
              'HTTP ${response.statusCode}',
            );
          }
          return SourceParsers.decode(
            source,
            post,
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
        } on AppFailure catch (e) {
          if (e.kind == FailureKind.cancelled) rethrow;
          last = e;
        } on TimeoutException {
          last = const AppFailure(FailureKind.timeout, '解析超时，请重试');
        } on http.ClientException catch (e) {
          last = AppFailure(FailureKind.network, '网络连接失败，请检查网络', e.message);
        } finally {
          active = false;
          client.close();
        }
      }
      _checkCancelled(cancellation);
      throw last;
    } finally {
      timer.cancel();
    }
  }

  static void _checkCancelled(ParseCancellation c) {
    if (c.isCancelled) throw const AppFailure(FailureKind.cancelled, '已取消解析');
  }

  static Future<http.Response> _fetch(
    http.Client client,
    ParseSource source,
    PostLink post,
    ParseCancellation cancellation,
    bool Function() active,
  ) async {
    final request = _request(source, post);
    if (source.kind == SourceKind.snap) {
      final homepage = request.url.resolve('/en2');
      final page = await client.get(
        homepage,
        headers: {'user-agent': 'Mozilla/5.0', 'accept': 'text/html'},
      );
      _checkCancelled(cancellation);
      if (!active()) throw const AppFailure(FailureKind.cancelled, '解析已结束');
      if (page.statusCode != 200) {
        throw const AppFailure(FailureKind.server, 'SnapTwitter 暂时不可用');
      }
      String? token;
      for (final input in RegExp(
        r'<input\b[^>]*>',
        caseSensitive: false,
      ).allMatches(utf8.decode(page.bodyBytes, allowMalformed: true))) {
        final attrs = <String, String>{};
        for (final a in RegExp(
          r'''([\w:-]+)\s*=\s*["']([^"']*)["']''',
        ).allMatches(input[0]!)) {
          attrs[a[1]!.toLowerCase()] = a[2]!;
        }
        if (attrs['name'] == 'token') token = attrs['value'];
      }
      if (token == null || token.isEmpty) {
        throw const AppFailure(FailureKind.server, '下载源需要验证或页面已变化，请切换其他源');
      }
      request.headers['referer'] = homepage.toString();
      request.bodyFields = {
        'url': post.canonicalUrl.toString(),
        'token': token
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'"),
      };
    }
    return client.send(request).then(http.Response.fromStream);
  }

  static String expand(String template, PostLink post) => template
      .replaceAll('{urlenc}', Uri.encodeComponent(post.canonicalUrl.toString()))
      .replaceAll('{url}', post.canonicalUrl.toString())
      .replaceAll('{id}', post.postId)
      .replaceAll('{user}', post.user);
  static http.Request _request(ParseSource source, PostLink post) {
    final endpoint = expand(source.endpoint, post);
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        endpoint.contains(RegExp(r'[{}]'))) {
      throw const AppFailure(FailureKind.malformed, '解析源地址无效');
    }
    final method =
        source.kind == SourceKind.xdl || source.kind == SourceKind.snap
        ? 'POST'
        : source.kind == SourceKind.scrape
        ? source.method.toUpperCase()
        : 'GET';
    if (!['GET', 'POST'].contains(method)) {
      throw const AppFailure(FailureKind.malformed, '解析源仅支持 GET 或 POST');
    }
    final request = http.Request(method, uri);
    request.headers['user-agent'] = source.kind == SourceKind.vx
        ? 'curl/8.5.0'
        : 'Mozilla/5.0';
    request.headers['accept'] = 'application/json,text/html;q=0.9,*/*;q=0.8';
    request.headers['referer'] = 'https://x.com/';
    if (source.kind == SourceKind.xdl) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode({'url': post.canonicalUrl.toString()});
    } else if (method == 'POST') {
      request.headers['content-type'] =
          'application/x-www-form-urlencoded; charset=utf-8';
      request.body = source.body.isEmpty
          ? 'url=${Uri.encodeComponent(post.canonicalUrl.toString())}'
          : expand(source.body, post);
    }
    return request;
  }

  Future<int?> probeSize(Uri url, ParseCancellation cancellation) async {
    final client = clientFactory();
    try {
      _checkCancelled(cancellation);
      final response = await Future.any<http.Response>([
        client
            .send(http.Request('HEAD', url))
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 3)),
        cancellation.whenCancelled.then(
          (_) => throw const AppFailure(FailureKind.cancelled, '已取消'),
        ),
      ]);
      return response.statusCode == 200
          ? int.tryParse(response.headers['content-length'] ?? '')
          : null;
    } on Exception {
      return null;
    } finally {
      client.close();
    }
  }
}
