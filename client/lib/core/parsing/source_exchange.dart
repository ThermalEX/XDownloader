import 'dart:convert';

import '../models/app_failure.dart';
import '../models/source.dart';
import 'parse_client.dart';

class SourceExchange {
  static const maxBytes = 512 * 1024;
  static const maxCustom = 50;
  static String encode(List<ParseSource> sources) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'xdownloader.sources',
        'version': 1,
        'sources': sources.map((s) => s.toJson()).toList(),
      });
  static List<ParseSource> decode(String text) {
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const AppFailure(FailureKind.malformed, '源配置不能超过 512 KiB');
    }
    try {
      final root = jsonDecode(text);
      if (root is! Map ||
          root['format'] != 'xdownloader.sources' ||
          root['version'] != 1 ||
          root['sources'] is! List) {
        throw const FormatException('Unsupported source format');
      }
      final rows = root['sources'] as List;
      if (rows.length > 100) throw const FormatException('Too many entries');
      return rows.map((raw) {
        final map = Map<String, dynamic>.from(raw as Map);
        final source = ParseSource.fromJson({
          ...map,
          'id': '',
          'builtin': false,
        });
        if (source.name.trim().isEmpty ||
            source.name.length > 120 ||
            source.endpoint.length > 4096 ||
            source.body.length > 65536 ||
            !['GET', 'POST'].contains(source.method.toUpperCase())) {
          throw const FormatException('Invalid source fields');
        }
        ParseClient.validateSource(source);
        return ParseSource(
          '',
          source.name.trim(),
          source.endpoint.trim(),
          source.kind,
          source.kind == SourceKind.xdl || source.kind == SourceKind.snap
              ? 'POST'
              : source.kind == SourceKind.scrape
              ? source.method.toUpperCase()
              : 'GET',
          source.body,
          false,
        );
      }).toList();
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(FailureKind.malformed, '源配置格式无效，请使用应用导出的 JSON');
    }
  }

  static String identity(ParseSource s) => jsonEncode([
    s.kind.name,
    s.endpoint.trim(),
    s.kind == SourceKind.xdl || s.kind == SourceKind.snap
        ? 'POST'
        : s.kind == SourceKind.scrape
        ? s.method.toUpperCase()
        : 'GET',
    s.kind == SourceKind.scrape && s.method.toUpperCase() == 'POST'
        ? s.body
        : '',
  ]);
}
