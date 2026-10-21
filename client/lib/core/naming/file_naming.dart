import 'dart:convert';

import '../models/media.dart';

class FileNaming {
  static const defaultTemplate = '{author}_{postId}_v{index}_{resolution}';
  static const variables = [
    'title',
    'author',
    'postId',
    'index',
    'width',
    'height',
    'resolution',
    'date',
    'time',
    'datetime',
  ];
  static String? validateTemplate(String template) {
    if (template.trim().isEmpty) return '请输入重命名模板';
    if (template.runes.length > 256) return '模板不能超过 256 个字符';
    final remainder = template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) => variables.contains(match[1]) ? '' : match[0]!,
    );
    if (remainder.contains(RegExp(r'[{}]'))) return '模板包含不支持或未闭合的变量';
    return null;
  }

  static String build(
    MediaResult result,
    MediaVariant variant, {
    String? template,
    bool useOriginalName = false,
    DateTime? now,
  }) {
    final author = String.fromCharCodes(result.author.runes.take(40))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    final size = variant.width > 0 && variant.height > 0
        ? '${variant.width}x${variant.height}'
        : 'MP4';
    return _format(useOriginalName ? '{title}' : template ?? defaultTemplate, {
      'title': result.title.isEmpty ? result.post.postId : result.title,
      'author': author.isEmpty ? 'X' : author,
      'postId': result.post.postId,
      'index': '${variant.mediaIndex}',
      'width': '${variant.width}',
      'height': '${variant.height}',
      'resolution': size,
      ..._dateValues(now ?? DateTime.now()),
    });
  }

  static String preview(String template, {DateTime? now}) => _format(template, {
    'title': '示例视频',
    'author': '示例作者',
    'postId': '1234567890123456789',
    'index': '1',
    'width': '1920',
    'height': '1080',
    'resolution': '1920x1080',
    ..._dateValues(now ?? DateTime.now()),
  });

  static Map<String, String> _dateValues(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date =
        '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
    final time = '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
    return {'date': date, 'time': time, 'datetime': '${date}_$time'};
  }

  static String _format(String template, Map<String, String> values) {
    final error = validateTemplate(template);
    if (error != null) throw FormatException(error);
    var name = template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => values[m[1]]!,
    );
    name = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^\.+|[. ]+$'), '')
        .replaceFirst(RegExp(r'\.mp4$', caseSensitive: false), '');
    if (name.isEmpty) name = 'X_${values['postId']}_v${values['index']}';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = 'X_$name';
    }
    final out = StringBuffer();
    var length = 0;
    for (final rune in name.runes) {
      final part = String.fromCharCode(rune),
          size = utf8.encode(String.fromCharCode(rune)).length;
      if (length + size > 176) break;
      out.write(part);
      length += size;
    }
    return '${out.toString().replaceAll(RegExp(r'[. ]+$'), '')}.mp4';
  }
}
