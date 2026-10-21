import '../core/models/app_failure.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/models/app_settings.dart';
import '../core/models/download.dart';
import '../core/models/source.dart';
import '../core/parsing/parse_client.dart';
import '../core/parsing/source_catalog.dart';
import '../platform/legacy_data_gateway.dart';
import 'storage/snapshot_store.dart';

class MigrationResult {
  const MigrationResult(this.imported, this.skipped, this.errors);
  final int imported, skipped;
  final List<AppFailure> errors;
}

class LegacyMigration {
  LegacyMigration(this.store, this.gateway);
  final SnapshotStore store;
  final LegacyDataGateway gateway;
  Future<MigrationResult> run() async {
    var imported = 0, skipped = 0;
    final errors = <AppFailure>[];
    try {
      if ((await store.read('migration'))['completed'] == true) {
        return const MigrationResult(0, 0, []);
      }
      final legacy = await gateway.read();
      final currentSources = await store.read('sources');
      final custom = <String, Map<String, dynamic>>{};
      for (final raw in currentSources['custom'] as List? ?? []) {
        final m = Map<String, dynamic>.from(raw as Map);
        custom[m['id'] as String] = m;
      }
      var validSources = 0;
      for (final raw in _entries(
        legacy.sources['custom'] as String?,
        '解析源',
        errors,
      )) {
        try {
          final m = Map<String, dynamic>.from(raw as Map);
          final kind = switch ('${m['kind']}'.toUpperCase()) {
            'XDL' => SourceKind.xdl,
            'FXTWITTER' => SourceKind.fx,
            'VXTWITTER' => SourceKind.vx,
            'SYNDICATION' => SourceKind.syndication,
            _ => SourceKind.scrape,
          };
          final name = m['name'] as String;
          final id = (m['id'] as String?)?.trim();
          final source = ParseSource(
            id == null || id.isEmpty ? _legacyId(name) : id,
            name,
            m['endpoint'] as String,
            kind,
            kind == SourceKind.xdl ? 'POST' : m['method'] as String? ?? 'GET',
            m['body'] as String? ?? '',
            false,
          );
          if (name.trim().isEmpty ||
              SourceCatalog.builtins.any((s) => s.id == source.id)) {
            throw const FormatException('Invalid custom source');
          }
          ParseClient.validateSource(source);
          custom.putIfAbsent(source.id, source.toJson);
          validSources++;
        } catch (e) {
          skipped++;
          errors.add(AppFailure(FailureKind.malformed, '一条旧版解析源无法导入', '$e'));
        }
      }
      final allIds = {
        ...SourceCatalog.builtins.map((s) => s.id),
        ...custom.keys,
      };
      final selected =
          currentSources['current'] ?? legacy.sources['current'] ?? 'xdl';
      await store.write('sources', {
        'custom': custom.values.toList(),
        'current': allIds.contains(selected) ? selected : 'xdl',
        'fallback':
            currentSources['fallback'] ?? legacy.sources['fallback'] ?? true,
      });
      imported += validSources;
      final currentSettings = await store.read('settings');
      await store.write('settings', {
        ...const AppSettings().toJson(),
        if (legacy.settings.containsKey('auto_clip'))
          'autoClipboard': legacy.settings['auto_clip'],
        ...currentSettings,
      });
      final currentDownloads = await store.read('downloads');
      final records = List<Object?>.from(
        currentDownloads['records'] as List? ?? [],
      );
      final ids = records
          .map((v) => ((v as Map)['request'] as Map)['taskId'])
          .toSet();
      final ignored = (currentDownloads['ignored'] as List? ?? []).toSet();
      var validHistory = 0;
      for (final raw in _entries(legacy.historyJson, '历史记录', errors)) {
        try {
          final m = Map<String, dynamic>.from(raw as Map);
          final name = m['name'] as String;
          if (name.trim().isEmpty) {
            throw const FormatException('Missing filename');
          }
          final time = (m['time'] as num?)?.toInt() ?? 0;
          final tweet = m['tweet'] as String? ?? '';
          final id =
              'legacy_${sha256.convert(utf8.encode(jsonEncode([name, tweet, time]))).toString().substring(0, 24)}';
          if (ignored.contains(id)) continue;
          if (!ids.contains(id)) {
            final file = await gateway.locateOwnedDownload(name);
            final size = RegExp(r'(\d+)\s*[x×]\s*(\d+)')
                .firstMatch(m['label'] as String? ?? '');
            final post = Uri.tryParse(tweet);
            final request = DownloadRequest(
              taskId: id,
              url: Uri(),
              displayName: name,
              headers: const {},
              mediaIndex: 1,
              postUrl: post != null && ['http', 'https'].contains(post.scheme)
                  ? post
                  : null,
              width: size == null ? null : int.parse(size[1]!),
              height: size == null ? null : int.parse(size[2]!),
            );
            records.add(
              DownloadRecord(
                request: request,
                phase: DownloadPhase.completed,
                legacy: true,
                createdAt: DateTime.fromMillisecondsSinceEpoch(time),
                savedFile: file,
                bytes: file?.bytes ?? (m['bytes'] as num?)?.toInt() ?? 0,
              ).toJson(),
            );
            ids.add(id);
          }
          validHistory++;
        } catch (e) {
          skipped++;
          errors.add(AppFailure(FailureKind.malformed, '一条旧版历史记录无法导入', '$e'));
        }
      }
      await store.write('downloads', {...currentDownloads, 'records': records});
      imported += validHistory;
      await store.write('migration', {
        'completed': errors.isEmpty,
        'imported': imported,
        'skipped': skipped,
        'errors': errors.map((e) => e.toString()).toList(),
      });
    } catch (e) {
      errors.add(
        e is AppFailure
            ? e
            : AppFailure(FailureKind.storage, '旧版数据尚未导入完成，可稍后重试', '$e'),
      );
    }
    return MigrationResult(imported, skipped, List.unmodifiable(errors));
  }

  static List<dynamic> _entries(
    String? text,
    String label,
    List<AppFailure> errors,
  ) {
    if (text == null || text.trim().isEmpty) return [];
    try {
      final parsed = jsonDecode(text);
      if (parsed is! List) throw const FormatException('Expected a list');
      return parsed;
    } catch (e) {
      errors.add(
        AppFailure(FailureKind.malformed, '旧版$label格式损坏，原数据已保留', '$e'),
      );
      return [];
    }
  }

  static String _legacyId(String name) {
    var base = name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = 'custom';
    if (base.length > 20) base = base.substring(0, 20);
    return 'c_$base';
  }
}
