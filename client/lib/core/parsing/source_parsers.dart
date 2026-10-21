import 'dart:convert';

import '../models/app_failure.dart';
import '../models/media.dart';
import '../models/source.dart';
import 'post_link.dart';

class SourceParsers {
  static MediaResult decode(ParseSource source, PostLink post, String text) {
    try {
      return _decode(source, post, text);
    } on AppFailure {
      rethrow;
    } on FormatException catch (e) {
      throw AppFailure(FailureKind.malformed, '解析源返回了无法识别的数据', e.message);
    } on TypeError catch (e) {
      throw AppFailure(FailureKind.malformed, '解析源数据格式不正确', e.toString());
    }
  }

  static MediaResult _decode(ParseSource source, PostLink post, String text) {
    final groups = <int, List<MediaVariant>>{};
    final seen = <String>{};
    var title = '', author = '', thumbnail = '';
    double duration = 0;
    void add(
      Object? raw,
      int index, {
      Object? width,
      Object? height,
      Object? bitrate,
    }) {
      final uri = Uri.tryParse(_string(raw).replaceAll('&amp;', '&'));
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          !uri.path.toLowerCase().endsWith('.mp4')) {
        return;
      }
      if (!seen.add('$index|$uri')) return;
      final size = RegExp(r'/(\d+)x(\d+)/').firstMatch(uri.path);
      final w = size == null ? _number(width).toInt() : int.parse(size[1]!);
      final h = size == null ? _number(height).toInt() : int.parse(size[2]!);
      (groups[index] ??= []).add(
        MediaVariant(index, w, h, uri, _number(bitrate).toInt(), 'mp4'),
      );
    }

    if (source.kind == SourceKind.scrape || source.kind == SourceKind.snap) {
      var markup = text;
      if (text.trimLeft().startsWith('{')) {
        final root = _map(jsonDecode(text));
        if (root['error'] == true ||
            (root['status'] != null && root['status'] != 'ok')) {
          throw const AppFailure(FailureKind.server, '下载源暂时无法解析或需要验证，请切换其他源');
        }
        if (root['data'] is String) markup = root['data'] as String;
      }
      final html = markup.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
      final mediaIds = <String, int>{};
      for (final match in RegExp(
        r'''https?://[^\s"'<>\\)\]}]+''',
        caseSensitive: false,
      ).allMatches(html)) {
        var raw = match[0]!.replaceFirst(RegExp(r'[.,;]+$'), '');
        var uri = Uri.tryParse(raw);
        if (uri?.host == 'dl.snapcdn.app') {
          uri = _signedMedia(uri!);
          if (uri == null) continue;
          raw = uri.toString();
        }
        if (uri == null || !uri.path.toLowerCase().endsWith('.mp4')) continue;
        final identity = uri.host.toLowerCase() == 'video.twimg.com'
            ? RegExp(r'^/(amplify_video|ext_tw_video)/(\d+)/')
                  .firstMatch(uri.path)
            : null;
        // CDN media IDs identify renditions. Unknown URLs stay separate rather
        // than silently treating unrelated videos as alternative qualities.
        final key = identity == null
            ? uri.toString()
            : '${uri.host}/${identity[1]}/${identity[2]}';
        final index = mediaIds.putIfAbsent(key, () => mediaIds.length + 1);
        add(raw, index);
      }
      String meta(String name) {
        for (final tag in RegExp(
          r'<meta\b[^>]*>',
          caseSensitive: false,
        ).allMatches(html)) {
          final attrs = <String, String>{};
          for (final attr in RegExp(
            r'''([\w:-]+)\s*=\s*["']([^"']*)["']''',
          ).allMatches(tag[0]!)) {
            attrs[attr[1]!.toLowerCase()] = attr[2]!;
          }
          if (attrs['property'] == name || attrs['name'] == name) {
            return _entities(attrs['content'] ?? '');
          }
        }
        return '';
      }

      title = meta('og:title');
      thumbnail = meta('og:image');
      if (title.isEmpty) {
        title = _entities(
          RegExp(
                r'<title[^>]*>(.*?)</title>',
                caseSensitive: false,
                dotAll: true,
              ).firstMatch(html)?[1] ??
              '',
        );
      }
      if (title.isEmpty) {
        title = _entities(
          RegExp(
                r'<h3\b[^>]*>(.*?)</h3>',
                caseSensitive: false,
                dotAll: true,
              ).firstMatch(html)?[1]?.replaceAll(RegExp(r'<[^>]+>'), '') ??
              '',
        );
      }
    } else {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('Expected JSON object');
      final root = _map(decoded);
      switch (source.kind) {
        case SourceKind.xdl:
          if (root['success'] != true) {
            final error = _string(root['error']);
            throw AppFailure(
              error.toLowerCase().contains('extract video')
                  ? FailureKind.noVideo
                  : FailureKind.server,
              '解析源未能获取视频',
              error,
            );
          }
          title = _string(root['title']);
          author = _string(root['author']);
          thumbnail = _string(root['thumbnail']);
          duration = _number(root['duration']);
          for (final raw in _list(root['videos'])) {
            final v = _map(raw);
            final index = _number(v['video_index']).toInt();
            add(
              v['direct_download_url'],
              index > 0 ? index : 1,
              width: v['width'],
              height: v['quality'],
              bitrate: v['bitrate'],
            );
            if (duration <= 0) duration = _number(v['video_duration']);
          }
        case SourceKind.fx:
          final code = _number(root['code']);
          if (code != 0 && code != 200) {
            throw const AppFailure(FailureKind.server, 'FxTwitter 暂时不可用');
          }
          if (root['tweet'] is! Map) {
            throw const FormatException('Missing tweet');
          }
          final tweet = _map(root['tweet']);
          title = _string(tweet['text']);
          author = _string(_map(tweet['author'])['name']);
          var index = 0;
          for (final raw in _list(_map(tweet['media'])['videos'])) {
            final video = _map(raw);
            index++;
            if (duration <= 0) duration = _number(video['duration']);
            if (thumbnail.isEmpty) thumbnail = _string(video['thumbnail_url']);
            for (final raw in _list(video['variants'])) {
              final v = _map(raw);
              add(
                v['url'],
                index,
                width: v['width'],
                height: v['height'],
                bitrate: v['bitrate'],
              );
            }
            add(
              video['url'],
              index,
              width: video['width'],
              height: video['height'],
            );
          }
        case SourceKind.syndication:
          final video = _map(root['video']);
          title = _string(root['text']);
          author = _string(_map(root['user'])['name']);
          thumbnail = _string(video['poster']);
          duration = _number(video['durationMs']) / 1000;
          for (final raw in _list(video['variants'])) {
            final v = _map(raw);
            add(v['src'], 1, bitrate: v['bitrate']);
          }
        case SourceKind.vx:
          title = _string(root['text']);
          author = _string(root['user_name']);
          var index = 0;
          for (final raw in _list(root['media_extended'])) {
            final v = _map(raw);
            if (!['video', 'gif'].contains(v['type'])) continue;
            index++;
            final size = _map(v['size']);
            add(v['url'], index, width: size['width'], height: size['height']);
            if (duration <= 0) duration = _number(v['duration_millis']) / 1000;
            if (thumbnail.isEmpty) thumbnail = _string(v['thumbnail_url']);
          }
        case SourceKind.scrape:
        case SourceKind.snap:
          break;
      }
    }
    if (groups.isEmpty) {
      throw const AppFailure(FailureKind.noVideo, '这个帖子没有可下载的视频');
    }
    final indices = groups.keys.toList()..sort();
    final image = Uri.tryParse(thumbnail);
    return MediaResult(
      post,
      title.trim().split('\n').first,
      author.trim(),
      image != null && ['http', 'https'].contains(image.scheme) ? image : null,
      duration > 0 ? Duration(milliseconds: (duration * 1000).round()) : null,
      indices.map((i) => MediaItem(i, groups[i]!)).toList(),
      source.id,
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static Uri? _signedMedia(Uri wrapper) {
    if (wrapper.scheme != 'https' ||
        wrapper.userInfo.isNotEmpty ||
        wrapper.path != '/get' ||
        (wrapper.hasPort && wrapper.port != 443)) {
      return null;
    }
    try {
      final token = wrapper.queryParameters['token'] ?? '';
      if (token.length > 32768) return null;
      final pieces = token.split('.');
      if (pieces.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))),
      );
      final url = payload is Map ? payload['url'] : null;
      if (url is! String) return null;
      final uri = Uri.tryParse(url);
      return uri != null &&
              uri.scheme == 'https' &&
              uri.host == 'video.twimg.com' &&
              uri.userInfo.isEmpty &&
              (!uri.hasPort || uri.port == 443) &&
              uri.path.toLowerCase().endsWith('.mp4')
          ? uri
          : null;
    } catch (_) {
      return null;
    }
  }

  static List<dynamic> _list(Object? value) => value is List ? value : [];
  static String _string(Object? value) => value is String ? value : '';
  static double _number(Object? value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return n.isFinite ? n : 0;
  }

  static String _entities(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
