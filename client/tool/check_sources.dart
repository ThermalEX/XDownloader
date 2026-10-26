import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';

/// Live availability is separate from deterministic fixture tests.
Future<void> main(List<String> args) async {
  final verifyMedia = args.contains('--verify-media');
  final inputs = args.where((arg) => arg != '--verify-media');
  final input = inputs.isEmpty
      ? 'https://x.com/9GAG/status/1661175429859012608'
      : inputs.first;
  final checks = SourceCatalog.builtins.map((source) async {
    final watch = Stopwatch()..start();
    try {
      final result = await ParseClient().parse(
        input,
        sources: [source],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      final media = verifyMedia
          ? await _checkMedia(result.items.first.variants.first.url)
          : null;
      stdout.writeln(
        jsonEncode({
          'source': source.id,
          'ok': media == null || media['mp4'] == true,
          'ms': watch.elapsedMilliseconds,
          'media': result.items.length,
          'mediaCheck': ?media,
          'variants': result.items.fold<int>(
            0,
            (n, m) => n + m.variants.length,
          ),
        }),
      );
      return media == null || media['mp4'] == true;
    } catch (e) {
      stdout.writeln(
        jsonEncode({
          'source': source.id,
          'ok': false,
          'ms': watch.elapsedMilliseconds,
          'error': '$e',
        }),
      );
      return false;
    }
  });
  if ((await Future.wait(checks)).contains(false)) exitCode = 1;
}

/// Inspect 32 bytes then cancel the stream, including when Range is ignored.
Future<Map<String, Object?>> _checkMedia(Uri url) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', url)
      ..headers.addAll({
        'user-agent': 'Mozilla/5.0',
        'referer': 'https://x.com/',
        'range': 'bytes=0-31',
      });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      bytes.addAll(chunk.take(32 - bytes.length));
      if (bytes.length == 32) break;
    }
    return {
      'status': response.statusCode,
      'host': url.host,
      'type': response.headers['content-type'],
      'range': response.headers['content-range'],
      'bytes': bytes.length,
      'mp4':
          [200, 206].contains(response.statusCode) &&
          bytes.length >= 8 &&
          String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp',
    };
  } finally {
    client.close();
  }
}
