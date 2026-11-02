import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/app_update.dart';
import '../../core/models/favorite_link.dart';
import '../../core/models/request_rotation.dart';
import '../../core/models/source.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/source_catalog.dart';
import '../../core/parsing/source_exchange.dart';

/// A bounded, immutable, portable snapshot. Operational and secret settings
/// are deliberately omitted even when the caller passes a full repository map.
class BackupArchive {
  BackupArchive._({
    required this.id,
    required this.createdAt,
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.data,
  }) : digest = _hash(data);

  static const maxBytes = 16 * 1024 * 1024;
  static const sections = {'favorites', 'settings', 'sources', 'updates'};
  static const _maxDepth = 32;
  static const _maxRows = 50000;
  static const _maxString = 65536;
  final String id, deviceId, deviceName, appVersion, digest;
  final DateTime createdAt;
  final Map<String, Map<String, Object?>> data;

  factory BackupArchive.create({
    required String id,
    required DateTime createdAt,
    required String deviceId,
    required String deviceName,
    required String appVersion,
    required Map<String, Map<String, Object?>> data,
  }) {
    _identifier(id);
    _identifier(deviceId);
    _text(deviceName, 120, nonempty: true);
    _text(appVersion, 120, nonempty: true);
    final value = BackupArchive._(
      id: id,
      createdAt: createdAt.toUtc(),
      deviceId: deviceId,
      deviceName: deviceName,
      appVersion: appVersion,
      data: sanitizeData(data),
    );
    if (utf8.encode(value.fileName).length > 240) {
      throw const FormatException('备份文件名不能超过 240 字节');
    }
    if (value.encode().length > maxBytes) {
      throw const FormatException('备份不能超过 16 MiB');
    }
    return value;
  }

  factory BackupArchive.decode(List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException('备份不能超过 16 MiB');
    try {
      final text = utf8.decode(bytes);
      _checkNesting(text);
      final root = _map(jsonDecode(text));
      _bounded(root);
      if (root['format'] != 'xdownloader.backup' ||
          root['schemaVersion'] != 1) {
        throw const FormatException('不支持的备份版本');
      }
      final payload = _map(root['data']);
      final declared = _list(root['sections']);
      if (declared.any((s) => s is! String) ||
          declared.toSet().length != declared.length ||
          declared.length != payload.length ||
          !declared.toSet().containsAll(payload.keys)) {
        throw const FormatException('备份内容分组不一致');
      }
      if (root['payloadSha256'] != _hash(payload)) {
        throw const FormatException('备份完整性校验失败');
      }
      final time = root['createdAt'];
      if (time is! String || !time.endsWith('Z')) {
        throw const FormatException('备份时间必须为 UTC');
      }
      return BackupArchive.create(
        id: root['archiveId'] as String,
        createdAt: DateTime.parse(time),
        deviceId: root['deviceId'] as String,
        deviceName: root['deviceName'] as String,
        appVersion: root['appVersion'] as String,
        data: {
          for (final entry in payload.entries) entry.key: _map(entry.value),
        },
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份格式无效');
    }
  }

  String get fileName =>
      'xdl_${createdAt.toIso8601String().replaceAll(RegExp(r'[:-]'), '')}_${deviceId}_$id.xdlbackup.json';

  List<int> encode() {
    final bytes = utf8.encode(
      jsonEncode({
        'format': 'xdownloader.backup',
        'schemaVersion': 1,
        'archiveId': id,
        'createdAt': createdAt.toIso8601String(),
        'deviceId': deviceId,
        'deviceName': deviceName,
        'appVersion': appVersion,
        'sections': data.keys.toList()..sort(),
        'payloadSha256': digest,
        'data': data,
      }),
    );
    if (bytes.length > maxBytes) throw const FormatException('备份不能超过 16 MiB');
    return bytes;
  }

  /// Shared validation for backup capture and pure restore planning.
  static Map<String, Map<String, Object?>> sanitizeData(
    Map<String, Map<String, Object?>> data,
  ) {
    try {
      _bounded(data);
      if (data.keys.any((key) => !sections.contains(key))) {
        throw const FormatException('未知的备份内容分组');
      }
      final result = <String, Map<String, Object?>>{};
      for (final entry in data.entries) {
        final clean = switch (entry.key) {
          'favorites' => _favorites(entry.value),
          'settings' => _settings(entry.value),
          'updates' => _updates(entry.value),
          'sources' => _sources(entry.value),
          _ => throw const FormatException('未知的备份内容分组'),
        };
        result[entry.key] = _freeze(clean) as Map<String, Object?>;
      }
      return Map.unmodifiable(result);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份数据无效');
    }
  }

  static Map<String, Object?> _favorites(Map<String, Object?> value) {
    final rows = _list(value.containsKey('items') ? value['items'] : []);
    final ids = <String>{};
    final items = <Map<String, Object?>>[];
    final categories = <String>[];
    for (final raw in _list(
      value.containsKey('categories') ? value['categories'] : [],
    )) {
      final category = _text(raw, 40, nonempty: true);
      if (categories.contains(category)) throw const FormatException('收藏分类重复');
      categories.add(category);
    }
    for (final raw in rows) {
      final item = FavoriteLink.fromJson(_map(raw));
      _text(item.title, 300);
      if (item.author != null) _text(item.author, 300);
      if (!ids.add(item.postId)) throw const FormatException('收藏编号重复');
      if (item.category.isNotEmpty && !categories.contains(item.category)) {
        categories.add(item.category);
      }
      if (item.coverUrl != null &&
          (!['https', 'http'].contains(item.coverUrl!.scheme) ||
              item.coverUrl!.host.isEmpty ||
              item.coverUrl!.userInfo.isNotEmpty)) {
        throw const FormatException('收藏封面地址无效');
      }
      items.add(item.toJson());
    }
    final sort = value['sort'] ?? 'defaultOrder';
    if (!['defaultOrder', 'newest', 'oldest', 'title'].contains(sort)) {
      throw const FormatException('收藏排序无效');
    }
    return {'items': items, 'categories': categories, 'sort': sort};
  }

  static const _settingKeys = {
    'themeMode',
    'handedness',
    'seedColor',
    'useDynamicColor',
    'autoClipboard',
    'playfulAvatar',
    'coverCacheLimitMb',
    'useOriginalFileName',
    'fileNameTemplate',
  };
  static Map<String, Object?> _settings(Map<String, Object?> value) {
    final clean = {
      for (final key in _settingKeys)
        if (value.containsKey(key)) key: value[key],
    };
    for (final key in [
      'useDynamicColor',
      'autoClipboard',
      'playfulAvatar',
      'useOriginalFileName',
    ]) {
      if (clean.containsKey(key) && clean[key] is! bool) {
        throw const FormatException('设置开关无效');
      }
    }
    if (clean.containsKey('themeMode') &&
        !['system', 'light', 'dark'].contains(clean['themeMode'])) {
      throw const FormatException('主题无效');
    }
    if (clean.containsKey('handedness') &&
        !['right', 'left'].contains(clean['handedness'])) {
      throw const FormatException('惯用手设置无效');
    }
    final color = clean['seedColor'];
    if (clean.containsKey('seedColor') &&
        (color is! int || color < 0 || color > 0xffffffff)) {
      throw const FormatException('主题色无效');
    }
    if (clean.containsKey('fileNameTemplate')) {
      _text(clean['fileNameTemplate'], 4096);
    }
    if (clean.containsKey('coverCacheLimitMb') &&
        clean['coverCacheLimitMb'] is! int) {
      throw const FormatException('封面缓存上限无效');
    }
    final normalized = AppSettings.fromJson(clean).toJson();
    return {for (final key in _settingKeys) key: normalized[key]};
  }

  static Map<String, Object?> _updates(Map<String, Object?> value) {
    for (final key in ['autoCheck', 'showUpdatePrompt']) {
      if (value.containsKey(key) && value[key] is! bool) {
        throw const FormatException('更新偏好开关无效');
      }
    }
    if (value.containsKey('channel') &&
        !['stable', 'beta'].contains(value['channel'])) {
      throw const FormatException('更新渠道无效');
    }
    final preferences = UpdatePreferences.fromJson({
      for (final key in ['channel', 'autoCheck', 'showUpdatePrompt'])
        if (value.containsKey(key)) key: value[key],
    }).toJson();
    return {
      for (final key in ['channel', 'autoCheck', 'showUpdatePrompt'])
        key: preferences[key],
    };
  }

  static Map<String, Object?> _sources(Map<String, Object?> value) {
    final rows = _list(value.containsKey('custom') ? value['custom'] : []);
    if (rows.length > SourceExchange.maxCustom) {
      throw const FormatException('最多保存 50 个自定义源');
    }
    final builtinIds = SourceCatalog.builtins.map((s) => s.id).toSet();
    final ids = <String>{};
    final custom = <Map<String, Object?>>[];
    for (final raw in rows) {
      final map = _map(raw);
      final source = ParseSource.fromJson(map);
      _identifier(source.id);
      _text(source.name, 120, nonempty: true);
      _text(source.endpoint, 4096, nonempty: true);
      _text(source.body, 65536);
      if (source.builtin ||
          builtinIds.contains(source.id) ||
          !ids.add(source.id) ||
          !['GET', 'POST'].contains(source.method.toUpperCase())) {
        throw const FormatException('自定义源编号或定义无效');
      }
      ParseClient.validateSource(source);
      custom.add(
        ParseSource(
          source.id,
          source.name.trim(),
          source.endpoint.trim(),
          source.kind,
          source.requestMethod,
          source.body,
          false,
        ).toJson(),
      );
    }
    final order = _list(value.containsKey('order') ? value['order'] : []);
    if (order.any((id) => id is! String) ||
        order.toSet().length != order.length) {
      throw const FormatException('解析源排序无效');
    }
    final current = value['current'] ?? 'xdl';
    if (current is! String) throw const FormatException('当前解析源无效');
    final fallback = value.containsKey('fallback') ? value['fallback'] : true;
    if (fallback is! bool) throw const FormatException('自动换源设置无效');
    final protection = !value.containsKey('protection')
        ? const RequestRotation()
        : RequestRotation.fromJson(_map(value['protection']));
    return {
      'custom': custom,
      'current': current,
      'order': order,
      'fallback': fallback,
      'protection': protection.toJson(),
    };
  }

  static String _identifier(Object? value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
      throw const FormatException('备份或源编号无效');
    }
    return value;
  }

  static String _text(Object? value, int limit, {bool nonempty = false}) {
    if (value is! String ||
        value.runes.length > limit ||
        (nonempty && value.trim().isEmpty)) {
      throw const FormatException('备份文本无效或过长');
    }
    return value;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map || value.keys.any((k) => k is! String)) {
      throw const FormatException('备份对象无效');
    }
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _list(Object? value) {
    if (value is! List || value.length > _maxRows) {
      throw const FormatException('备份条目无效或过多');
    }
    return List<Object?>.from(value);
  }

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map((k, v) => MapEntry(k as String, _freeze(v))),
      );
    }
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static String _hash(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
  static void _bounded(Object? root) {
    var nodes = 0;
    void visit(Object? value, int depth) {
      if (++nodes > 400000 || depth > _maxDepth) {
        throw const FormatException('备份嵌套或条目过多');
      }
      if (value is String) {
        _text(value, _maxString);
      } else if (value is Map) {
        if (value.length > _maxRows) throw const FormatException('备份条目过多');
        for (final entry in value.entries) {
          _text(entry.key, 256);
          visit(entry.value, depth + 1);
        }
      } else if (value is List) {
        if (value.length > _maxRows) throw const FormatException('备份条目过多');
        for (final entry in value) {
          visit(entry, depth + 1);
        }
      } else if (value != null &&
          value is! bool &&
          (value is! num || !value.isFinite)) {
        throw const FormatException('备份值无效');
      }
    }

    visit(root, 0);
  }

  static void _checkNesting(String text) {
    var depth = 0, stringLength = 0;
    var quoted = false, escaped = false;
    for (final unit in text.codeUnits) {
      if (quoted) {
        if (++stringLength > _maxString * 6) {
          throw const FormatException('备份字符串过长');
        }
        if (escaped) {
          escaped = false;
        } else if (unit == 92) {
          escaped = true;
        } else if (unit == 34) {
          quoted = false;
        }
      } else if (unit == 34) {
        quoted = true;
        stringLength = 0;
      } else if (unit == 91 || unit == 123) {
        if (++depth > _maxDepth) throw const FormatException('备份嵌套过深');
      } else if (unit == 93 || unit == 125) {
        depth--;
      }
    }
  }
}
