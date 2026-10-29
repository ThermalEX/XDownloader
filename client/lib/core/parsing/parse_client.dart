import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media.dart';
import '../models/source.dart';
import '../models/app_failure.dart';
import 'post_link.dart';
import 'source_parsers.dart';
import 'request_profiles.dart';

class ParseCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class ParseClient {
  ParseClient({
    http.Client Function()? clientFactory,
    this.onAttempt,
    RequestProfiles? requestProfiles,
  }) : clientFactory = clientFactory ?? http.Client.new,
       requestProfiles = requestProfiles ?? RequestProfiles();
  final http.Client Function() clientFactory;
  final RequestProfiles requestProfiles;
  final void Function(String sourceId, bool success)? onAttempt;
  void _report(String id, bool success) {
    try {
      onAttempt?.call(id, success);
    } catch (_) {
      /* Metrics never gate parsing. */
    }
  }

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
      var attempts = 0;
      for (final source in autoFallback ? sources : sources.take(1)) {
        _checkCancelled(cancellation);
        if (deadline.isCompleted) {
          throw const AppFailure(FailureKind.timeout, '解析超时，请重试');
        }
        final cooling = requestProfiles.cooldownRemaining(source.id);
        if (cooling > Duration.zero) {
          last = AppFailure(
            FailureKind.server,
            '解析源限流冷却中，请稍后重试',
            '剩余 ${(cooling.inMilliseconds / 1000).ceil()} 秒',
          );
          continue;
        }
        if (attempts++ >= 5) break;
        final profile = source.kind == SourceKind.vx
            ? null
            : requestProfiles.begin(source.id);
        final client = clientFactory();
        var active = true;
        var completed = false;
        try {
          final response = await Future.any<http.Response>([
            _fetch(
              client,
              source,
              post,
              cancellation,
              () => active,
              profile?.headers ?? const {},
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
            throw _httpFailure(response);
          }
          final result = SourceParsers.decode(
            source,
            post,
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
          _report(source.id, true);
          completed = true;
          return result;
        } on AppFailure catch (e) {
          if (e.kind == FailureKind.cancelled) rethrow;
          completed = true;
          _report(source.id, false);
          last = e;
        } on TimeoutException {
          completed = true;
          _report(source.id, false);
          last = const AppFailure(FailureKind.timeout, '解析超时，请重试');
        } on http.ClientException catch (e) {
          _checkCancelled(cancellation);
          completed = true;
          _report(source.id, false);
          last = AppFailure(FailureKind.network, '网络连接失败，请检查网络', e.message);
        } finally {
          active = false;
          client.close();
          if (completed && !cancellation.isCancelled && profile != null) {
            requestProfiles.complete(profile);
          }
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

  Future<http.Response> _fetch(
    http.Client client,
    ParseSource source,
    PostLink post,
    ParseCancellation cancellation,
    bool Function() active,
    Map<String, String> profileHeaders,
  ) async {
    final request = _request(source, post)..headers.addAll(profileHeaders);
    if (source.kind == SourceKind.snap) {
      final homepage = request.url.resolve('/en2');
      final bootstrap = http.Request('GET', homepage)
        ..headers.addAll({
          'user-agent': 'Mozilla/5.0',
          'accept': 'text/html',
          ...profileHeaders,
        });
      final page = await _send(
        client,
        bootstrap,
        source.id,
        cancellation,
        active,
      );
      if (page.statusCode != 200) {
        throw _httpFailure(page);
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
    return _send(client, request, source.id, cancellation, active);
  }

  Future<http.Response> _send(
    http.Client client,
    http.Request request,
    String sourceId,
    ParseCancellation cancellation,
    bool Function() active,
  ) async {
    _checkCancelled(cancellation);
    if (!active()) throw const AppFailure(FailureKind.cancelled, '解析已结束');
    final response = await client.send(request);
    if (cancellation.isCancelled || !active()) {
      await response.stream.listen((_) {}).cancel();
      throw const AppFailure(FailureKind.cancelled, '解析已结束');
    }
    requestProfiles.recordResponse(
      sourceId,
      response.statusCode,
      response.headers,
    );
    // Error pages are not parser input. Cancel their bodies immediately, even
    // if the server stalls or resets them after sending Retry-After.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen((_) {}).cancel();
      return http.Response('', response.statusCode, headers: response.headers);
    }
    final body = await http.Response.fromStream(response);
    _checkCancelled(cancellation);
    if (!active()) throw const AppFailure(FailureKind.cancelled, '解析已结束');
    return body;
  }

  static AppFailure _httpFailure(http.Response response) => AppFailure(
    response.statusCode == 404 ? FailureKind.noVideo : FailureKind.server,
    response.statusCode == 429 ||
            (response.statusCode == 503 &&
                response.headers.containsKey('retry-after'))
        ? '解析源限流冷却中，请稍后重试'
        : '解析源暂时不可用',
    'HTTP ${response.statusCode}',
  );

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
    final method = source.requestMethod;
    if (!['GET', 'POST'].contains(method)) {
      throw const AppFailure(FailureKind.malformed, '解析源仅支持 GET 或 POST');
    }
    final request = http.Request(method, uri);
    request.headers['user-agent'] = source.kind == SourceKind.vx
        ? 'curl/8.5.0'
        : 'Mozilla/5.0';
    request.headers['accept'] = 'application/json,text/html;q=0.9,*/*;q=0.8';
    request.headers['referer'] = 'https://x.com/';
    if (source.kind == SourceKind.xdl || source.kind == SourceKind.tweetdl) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode({'url': post.canonicalUrl.toString()});
    } else if (source.kind == SourceKind.twmate) {
      request.bodyFields = {
        'page': post.canonicalUrl.toString(),
        'ftype': 'all',
        'ajax': '1',
      };
    } else if (method == 'POST') {
      request.headers['content-type'] =
          'application/x-www-form-urlencoded; charset=utf-8';
      request.body = source.body.isEmpty
          ? 'url=${Uri.encodeComponent(post.canonicalUrl.toString())}'
          : expand(source.body, post);
    }
    return request;
  }

  /// Verify only the initial MP4 bytes; abort the stream rather than downloading it.
  Future<void> verifyMedia(Uri url, ParseCancellation cancellation) async {
    _checkCancelled(cancellation);
    if (!['https', 'http'].contains(url.scheme) || url.host.isEmpty) {
      throw const AppFailure(FailureKind.invalidLink, '视频地址无效');
    }
    final client = clientFactory();
    StreamIterator<List<int>>? chunks;
    var active = true;
    Future<void> inspect() async {
      final request =
          http.AbortableRequest(
              'GET',
              url,
              abortTrigger: cancellation.whenCancelled,
            )
            ..headers.addAll({
              'user-agent': 'Mozilla/5.0',
              'referer': 'https://x.com/',
              'range': 'bytes=0-31',
            });
      final response = await client.send(request);
      if (!active || cancellation.isCancelled) {
        await response.stream.listen((_) {}).cancel();
        throw const AppFailure(FailureKind.cancelled, '已取消检测');
      }
      if (![200, 206].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        throw AppFailure(
          FailureKind.server,
          '视频地址返回 HTTP ${response.statusCode}',
        );
      }
      final bytes = <int>[];
      final iterator = chunks = StreamIterator(response.stream);
      while (bytes.length < 32 && await iterator.moveNext()) {
        _checkCancelled(cancellation);
        bytes.addAll(iterator.current.take(32 - bytes.length));
      }
      _checkCancelled(cancellation);
      if (!active) throw const AppFailure(FailureKind.cancelled, '检测已结束');
      if (bytes.length < 8 ||
          String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
        throw const AppFailure(FailureKind.malformed, '地址未返回有效 MP4 视频');
      }
    }

    try {
      await Future.any<void>([
        inspect().timeout(const Duration(seconds: 5)),
        cancellation.whenCancelled.then(
          (_) => throw const AppFailure(FailureKind.cancelled, '已取消检测'),
        ),
      ]);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, '视频验证超时');
    } on http.ClientException {
      _checkCancelled(cancellation);
      throw const AppFailure(FailureKind.network, '视频地址无法访问');
    } finally {
      active = false;
      client.close();
      await chunks?.cancel();
    }
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
