import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/naming/file_naming.dart';
import 'package:xdownloader/core/parsing/post_link.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';
import 'package:xdownloader/core/parsing/source_parsers.dart';

void main() {
  final post = PostLink(
    '123456',
    'author',
    Uri.parse('https://x.com/author/status/123456'),
  );
  test('normalizes shared mobile links and rejects deceptive domains', () {
    for (final text in [
      '分享 https://mobile.twitter.com/author/status/123456?s=20。',
      'x.com/author/status/123456',
      'https://x.com/i/web/status/123456',
    ]) {
      expect(PostLink.tryParse(text)?.postId, '123456');
    }
    for (final text in [
      'https://evilx.com/a/status/123456',
      'https://x.com.evil/a/status/123456',
      'https://evil.test/x.com/a/status/123456',
      'https://x.com/a/status/12',
      'https://x.com/a/status/123456oops',
    ]) {
      expect(PostLink.tryParse(text), isNull, reason: text);
    }
  });
  MediaResult fixture(String id, String path) => SourceParsers.decode(
    SourceCatalog.builtins.firstWhere((s) => s.id == id),
    post,
    File('test/fixtures/$path').readAsStringSync(),
  );
  test('groups two videos without mixing renditions', () {
    final result = fixture('xdl', 'xdl_two.json');
    expect(result.items.map((m) => m.index), [1, 2]);
    expect(result.items.first.variants.every((v) => v.mediaIndex == 1), isTrue);
    expect(result.items.first.variants.first.width, 1280);
    expect(result.items.first.variants.first.height, 720);
    expect(result.items.first.variants.last.height, 360);
    expect(() => result.items.clear(), throwsUnsupportedError);
  });
  test('scrape keeps each CDN media identity separate across renditions', () {
    final result = fixture('twitsave', 'scrape_two.html');
    expect(result.items, hasLength(3));
    expect(result.items[0].variants.map((v) => v.width), [1280, 640]);
    expect(result.items[1].variants.map((v) => v.height), [1280, 640]);
    expect(result.items[2].variants, hasLength(1));
    expect(
      result.items[0].variants.every((v) => v.url.path.contains('/111/')),
      isTrue,
    );
    expect(
      result.items[1].variants.every((v) => v.url.path.contains('/222/')),
      isTrue,
    );
  });
  test('preserves CJK in filenames and distinguishes media', () {
    final result = fixture('xdl', 'xdl_two.json');
    final a = FileNaming.build(result, result.items[0].variants.first);
    final b = FileNaming.build(result, result.items[1].variants.first);
    expect(result.title, '中文 CafÃ©');
    expect(a, contains('中文'));
    expect(a, contains('1280x720'));
    expect(a, contains('123456'));
    expect(a, isNot(b));
  });
  test('normalizes all five source formats and excludes playlists', () {
    for (final row in [
      ('fx', 'fx_two.json', 2),
      ('syndication', 'syndication_one.json', 1),
      ('vx', 'vx_two.json', 2),
      ('twitsave', 'scrape_one.html', 1),
    ]) {
      final result = fixture(row.$1, row.$2);
      expect(result.items.length, row.$3);
      expect(result.title, contains('中文'));
      expect(
        result.items
            .expand((i) => i.variants)
            .any((v) => v.url.path.endsWith('.m3u8')),
        isFalse,
      );
    }
  });
  test('empty and malformed responses produce typed failures', () {
    for (final text in ['{}', '{"success":true,"videos":[]}', '{bad']) {
      expect(
        () => SourceParsers.decode(SourceCatalog.builtins.first, post, text),
        throwsA(isA<AppFailure>()),
      );
    }
  });
}
