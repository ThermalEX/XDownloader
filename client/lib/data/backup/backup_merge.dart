import '../../core/models/source.dart';
import '../../core/parsing/source_catalog.dart';
import '../../core/parsing/source_exchange.dart';
import 'backup_archive.dart';

/// Pure restore planning; the caller commits these selected snapshot groups
/// together only after its safety archive and stale-preview checks succeed.
class BackupMerge {
  static Map<String, Map<String, Object?>> plan(
    Map<String, Map<String, Object?>> local,
    Map<String, Map<String, Object?>> incoming, {
    required bool replace,
    required bool preferArchive,
    required Set<String> sections,
  }) {
    if (sections.any((s) => !BackupArchive.sections.contains(s))) {
      throw const FormatException('未知的恢复分组');
    }
    final archive = BackupArchive.sanitizeData(incoming);
    final current = BackupArchive.sanitizeData({
      for (final entry in local.entries)
        if (BackupArchive.sections.contains(entry.key)) entry.key: entry.value,
    });
    final result = <String, Map<String, Object?>>{};
    for (final section in sections) {
      final remote = archive[section];
      if (remote == null) continue;
      final here = current[section];
      final adopt = replace || preferArchive || here == null;
      if (section == 'settings') {
        result[section] = {...?local[section], ...(adopt ? remote : here)};
      } else if (section == 'sources') {
        result[section] = _sources(
          here,
          remote,
          replace: replace,
          preferArchive: preferArchive,
        );
      } else if (section == 'favorites' && !replace && here != null) {
        final rows = <String, Map<String, Object?>>{};
        for (final item in here['items'] as List) {
          final row = _map(item);
          rows[row['postId'] as String] = row;
        }
        for (final item in remote['items'] as List) {
          final row = _map(item), id = row['postId'] as String;
          if (!rows.containsKey(id) || preferArchive) rows[id] = row;
        }
        result[section] = {
          'items': rows.values.toList(),
          'categories': {
            ...here['categories'] as List,
            ...remote['categories'] as List,
          }.toList(),
          'sort': adopt ? remote['sort'] : here['sort'],
        };
      } else {
        result[section] = {...(adopt ? remote : here)};
      }
    }
    return result;
  }

  static Map<String, Object?> _sources(
    Map<String, Object?>? local,
    Map<String, Object?> incoming, {
    required bool replace,
    required bool preferArchive,
  }) {
    final builtins = {for (final s in SourceCatalog.builtins) s.id: s};
    final locals = replace ? <ParseSource>[] : _custom(local);
    final remote = _custom(incoming);
    final chosen = {for (final s in locals) s.id: s};
    // Choose the complete winning definition for each ID before deduplication.
    // Looking at identities that a later conflict removes can otherwise retain
    // the losing definition or make the result depend on incoming row order.
    for (final source in remote) {
      if (!chosen.containsKey(source.id) || preferArchive) {
        chosen[source.id] = source;
      }
    }
    final identities = {
      for (final s in builtins.values) SourceExchange.identity(s): s.id,
    };
    final localMap = <String, String>{};
    final next = <String, ParseSource>{};
    for (final source in chosen.values) {
      final identity = SourceExchange.identity(source);
      final existing = identities[identity];
      localMap[source.id] = existing ?? source.id;
      if (existing == null) {
        next[source.id] = source;
        identities[identity] = source.id;
      }
    }
    // Both namespaces now refer to the same resolved per-ID definitions.
    final remoteMap = localMap;
    if (next.length > SourceExchange.maxCustom) {
      throw const FormatException('最多保存 50 个自定义源，未恢复任何条目');
    }
    final valid = {...builtins.keys, ...next.keys};
    String? reference(Object? value, Map<String, String> mapping) {
      if (value is! String) return null;
      final id = mapping[value] ?? value;
      return valid.contains(id) ? id : null;
    }

    final adopt = replace || preferArchive || local == null;
    final config = adopt ? incoming : local;
    final mapping = adopt ? remoteMap : localMap;
    final selected = reference(config['current'], mapping) ?? 'xdl';
    final order = <String>{};
    final priority = replace ? incoming : local;
    final priorityMap = replace ? remoteMap : localMap;
    if (priority != null) {
      for (final raw in priority['order'] as List) {
        final id = reference(raw, priorityMap);
        if (id != null) order.add(id);
      }
    }
    // Keep existing priorities and append new definitions, with every built-in
    // supplied from this application rather than the archive's code snapshot.
    order.addAll(builtins.keys);
    for (final source in locals) {
      final id = reference(source.id, localMap);
      if (id != null) order.add(id);
    }
    for (final raw in incoming['order'] as List) {
      final id = reference(raw, remoteMap);
      if (id != null) order.add(id);
    }
    order.addAll(next.keys);
    return {
      'custom': next.values.map((s) => s.toJson()).toList(),
      'current': selected,
      'fallback': config['fallback'],
      'order': order.toList(),
      'protection': config['protection'],
    };
  }

  static Map<String, Object?> _map(Object? value) =>
      Map<String, Object?>.from(value as Map);
  static List<ParseSource> _custom(Map<String, Object?>? value) =>
      ((value?['custom'] as List?) ?? [])
          .map((raw) => ParseSource.fromJson(_map(raw)))
          .toList();
}
