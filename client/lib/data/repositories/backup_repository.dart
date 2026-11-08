import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../platform/backup_platform.dart';
import '../backup/backup_archive.dart';
import '../backup/backup_merge.dart';
import '../backup/webdav_client.dart';
import '../storage/snapshot_store.dart';
import 'favorite_repository.dart';
import 'settings_repository.dart';
import 'source_repository.dart';
import 'update_repository.dart';

enum BackupLocation { local, cloud, both }

class LocalBackup {
  const LocalBackup(this.archive, this.bytes);
  final BackupArchive archive;
  final int bytes;
  String get fileName => archive.fileName;
}

class RestorePreview {
  const RestorePreview({
    required this.archive,
    required this.before,
    required this.groups,
    required this.replace,
    required this.preferArchive,
    required this.generation,
  });
  final BackupArchive archive;
  final Map<String, Map<String, Object?>> before, groups;
  final bool replace, preferArchive;
  final int generation;
}

typedef WebDavFactory = WebDavClient Function(
  WebDavConfig,
  String,
  bool Function(),
);

/// Authoritative backup operations. Every public data action checks privacy,
/// including after awaits; widgets are not trusted to enforce the restriction.
class BackupRepository extends ChangeNotifier {
  BackupRepository({
    required this.store,
    required this.settings,
    required this.favorites,
    required this.sources,
    required this.updates,
    BackupPlatform? platform,
    WebDavFactory? clientFactory,
    Directory? directory,
    this.appVersion = '2.16.0',
  }) : platform = platform ?? BackupPlatform(),
       directory = directory ?? Directory('${store.directory.path}/backups'),
       _clientFactory =
           clientFactory ??
           ((c, p, cancelled) =>
               WebDavClient(config: c, password: p, isCancelled: cancelled)) {
    settings.addListener(_privacyChanged);
  }

  final SnapshotStore store;
  final SettingsRepository settings;
  final FavoriteRepository favorites;
  final SourceRepository sources;
  final UpdateRepository updates;
  final BackupPlatform platform;
  final Directory directory;
  final String appVersion;
  final WebDavFactory _clientFactory;
  WebDavConfig? _config;
  WebDavConfig? get config => _config;
  String _deviceId = _id(), _deviceName = 'Android', _credentialKey = '';
  String get deviceName => _deviceName;
  bool _autoCheck = false, _busy = false, _disposed = false;
  bool get autoCheck => _autoCheck;
  bool get busy => _busy;
  bool get isPrivate => settings.privacyGuarded;
  int _epoch = 0, _previewGeneration = 0;
  String? _status, _error;
  DateTime? _recentBackupAt, _recentCheckAt;
  DateTime? get recentBackupAt => isPrivate ? null : _recentBackupAt;
  DateTime? get recentCheckAt => isPrivate ? null : _recentCheckAt;
  String? get status => isPrivate ? null : _status;
  String? get error => isPrivate ? null : _error;
  List<LocalBackup> _local = [];
  List<WebDavEntry> _remote = [];
  final _handled = <String>{};
  final _downloadedFrom = <String, String>{};
  int get pendingCloudCount => isPrivate
      ? 0
      : _remote.where((e) => !_handled.contains(e.fingerprint)).length;
  List<LocalBackup> get localArchives =>
      isPrivate ? const [] : List.unmodifiable(_local);
  List<WebDavEntry> get remoteEntries =>
      isPrivate ? const [] : List.unmodifiable(_remote);
  WebDavClient? _activeClient;

  static String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check([int? epoch]) {
    if (_disposed || isPrivate || (epoch != null && epoch != _epoch)) {
      throw const AppFailure(FailureKind.cancelled, '隐私模式已开启或操作已取消');
    }
  }

  void _privacyChanged() {
    if (isPrivate) {
      _epoch++;
      _previewGeneration++;
      _activeClient?.close();
      unawaited(platform.cancel().catchError((Object _) {}));
      _local = [];
      _remote = [];
      _status = null;
      _error = null;
    }
    _notify();
  }

  Future<T> _run<T>(Future<T> Function(int epoch) action) async {
    _check();
    if (_busy) throw const AppFailure(FailureKind.cancelled, '请等待当前备份操作完成');
    final epoch = ++_epoch;
    _busy = true;
    _error = null;
    _notify();
    try {
      return await action(epoch);
    } catch (e) {
      if (!isPrivate && !_disposed) {
        _error = e is AppFailure
            ? e.message
            : e is WebDavException
            ? e.message
            : e is FormatException
            ? e.message
            : '备份操作失败，请重试';
      }
      rethrow;
    } finally {
      _activeClient?.close();
      _activeClient = null;
      _busy = false;
      _notify();
    }
  }

  Future<void> initialize() async {
    final m = await store.read('sync');
    _deviceId = m['deviceId'] as String? ?? _deviceId;
    _deviceName = m['deviceName'] as String? ?? 'Android';
    _credentialKey = m['credentialKey'] as String? ?? '';
    _autoCheck = m['autoCheck'] == true;
    _recentBackupAt = DateTime.tryParse(m['recentBackupAt'] as String? ?? '');
    _recentCheckAt = DateTime.tryParse(m['recentCheckAt'] as String? ?? '');
    if (m['config'] case final Map value) {
      _config = WebDavConfig.fromJson(Map<String, Object?>.from(value));
    }
    _handled.addAll((m['handled'] as List? ?? []).cast<String>());
    _downloadedFrom.addAll(
      (m['downloadedFrom'] as Map? ?? {}).cast<String, String>(),
    );
    if (m.isEmpty) await _persist();
    if (!isPrivate) await refreshLocal();
  }

  Future<void> _persist() => store.write('sync', {
    'deviceId': _deviceId,
    'deviceName': _deviceName,
    'credentialKey': _credentialKey,
    'config': _config?.toJson(),
    'autoCheck': _autoCheck,
    'recentBackupAt': _recentBackupAt?.toUtc().toIso8601String(),
    'recentCheckAt': _recentCheckAt?.toUtc().toIso8601String(),
    'handled': _handled.toList(),
    'downloadedFrom': _downloadedFrom,
  });

  Future<void> configure({
    required WebDavConfig config,
    required String password,
    required String deviceName,
    required bool autoCheck,
  }) => _run((epoch) async {
    final name = deviceName.trim();
    if (name.isEmpty || name.runes.length > 120) {
      throw const FormatException('设备名称需为 1–120 字');
    }
    final keepPassword =
        password.isEmpty &&
        _credentialKey.isNotEmpty &&
        _config?.endpoint == config.endpoint &&
        _config?.username == config.username;
    final key = keepPassword ? _credentialKey : _id();
    if (!keepPassword) {
      await platform.writePassword(password, key: key);
    }
    _check(epoch);
    // A fresh immutable secret slot is referenced only by a committed config.
    // Failed/config-cancelled saves cannot replace the active account password.
    final next = <String, Object?>{
      'deviceId': _deviceId,
      'deviceName': name,
      'credentialKey': key,
      'config': config.toJson(),
      'autoCheck': autoCheck,
      'recentBackupAt': _recentBackupAt?.toUtc().toIso8601String(),
      'handled': <String>[],
      'downloadedFrom': <String, String>{},
    };
    await store.write('sync', next);
    _config = config;
    _deviceName = name;
    _credentialKey = key;
    _autoCheck = autoCheck;
    _recentCheckAt = null;
    _handled.clear();
    _downloadedFrom.clear();
    _remote = [];
    _previewGeneration++;
    _status = 'WebDAV 配置已保存';
  });

  Future<void> setAutoCheck(bool value) => _run((epoch) async {
    final previous = _autoCheck;
    _autoCheck = value;
    try {
      await _persist();
    } catch (_) {
      _autoCheck = previous;
      rethrow;
    }
  });

  Future<WebDavClient> _client(int epoch) async {
    _check(epoch);
    final config = _config;
    if (config == null || _credentialKey.isEmpty) {
      throw const FormatException('请先配置 WebDAV');
    }
    final password = await platform.readPassword(key: _credentialKey);
    _check(epoch);
    return _activeClient = _clientFactory(
      config,
      password,
      () => _disposed || isPrivate || epoch != _epoch,
    );
  }

  Future<void> testConnection() => _run((epoch) async {
    await (await _client(epoch)).testConnection();
    _check(epoch);
    _status = 'WebDAV 连接与读写正常';
  });

  Future<Map<String, Map<String, Object?>>> _capture() async => {
    for (final key in BackupArchive.sections) key: await store.read(key),
  };
  BackupArchive _archive(Map<String, Map<String, Object?>> data) =>
      BackupArchive.create(
        id: _id(),
        createdAt: DateTime.now().toUtc(),
        deviceId: _deviceId,
        deviceName: _deviceName,
        appVersion: appVersion,
        data: data,
      );
  static String _fingerprint(Map<String, Map<String, Object?>> data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  Future<void> _scanLocal(int epoch) async {
    await directory.create(recursive: true);
    final next = <LocalBackup>[];
    var invalid = 0;
    await for (final entity in directory.list(followLinks: false)) {
      _check(epoch);
      if (entity is! File || !entity.path.endsWith('.zip')) continue;
      try {
        final length = await entity.length();
        if (length > BackupArchive.maxBytes) {
          throw const FormatException('oversize');
        }
        final archive = BackupArchive.decode(await entity.readAsBytes());
        // Application-owned filenames are derived from validated metadata.
        if (entity.uri.pathSegments.last != archive.fileName) {
          throw const FormatException('filename');
        }
        next.add(LocalBackup(archive, length));
      } on FormatException {
        invalid++;
      }
    }
    _check(epoch);
    next.sort((a, b) {
      final order = b.archive.createdAt.compareTo(a.archive.createdAt);
      return order == 0 ? a.archive.id.compareTo(b.archive.id) : order;
    });
    _local = next;
    if (invalid > 0) _status = '$invalid 份无效存档已保留，未加载';
  }

  Future<void> refreshLocal() => _run(_scanLocal);
  Future<void> refreshRemote() => _run((epoch) async {
    final entries = await (await _client(epoch)).list();
    _check(epoch);
    _remote = entries;
    _recentCheckAt = DateTime.now().toUtc();
    await _persist();
    _status = '云端存档已刷新';
  });
  Future<void> checkAtStartup() async {
    if (!_autoCheck || _config == null || isPrivate || _busy) return;
    try {
      await refreshRemote();
    } catch (_) {
      /* Details are available in settings. */
    }
  }

  Future<void> _saveLocal(BackupArchive archive, int epoch) async {
    _check(epoch);
    // Privacy intentionally discards the in-memory catalogue. Rebuild it from
    // durable files before enforcing cross-filename archive ID uniqueness.
    await _scanLocal(epoch);
    await directory.create(recursive: true);
    final bytes = archive.encode();
    // IDs cannot silently alias a different archive, even under another name.
    for (final old in _local.where((e) => e.archive.id == archive.id)) {
      if (!listEquals(old.archive.encode(), bytes)) {
        throw const FormatException('存档 ID 冲突，原文件已保留');
      }
    }
    final file = File('${directory.path}/${archive.fileName}');
    if (await file.exists()) {
      if (!listEquals(await file.readAsBytes(), bytes)) {
        throw const FormatException('存档内容冲突，原文件已保留');
      }
      return;
    }
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      _check(epoch);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<BackupArchive> create({
    Set<String>? sections,
    BackupLocation location = BackupLocation.both,
  }) => _run((epoch) async {
    final selected = sections ?? BackupArchive.sections;
    if (selected.isEmpty || !BackupArchive.sections.containsAll(selected)) {
      throw const FormatException('请选择备份内容');
    }
    final archive = await store.mutations.run(() async {
      _check(epoch);
      final data = await _capture();
      _check(epoch);
      return _archive({for (final key in selected) key: data[key]!});
    });
    await _saveLocal(archive, epoch);
    await _scanLocal(epoch);
    _recentBackupAt = DateTime.now().toUtc();
    await _persist();
    _status = '本地已保存';
    _notify();
    if (location != BackupLocation.local) {
      try {
        await _upload(archive, epoch);
      } catch (_) {
        _status = '本地已保存，云端失败，可稍后重新上传';
        rethrow;
      }
      if (location == BackupLocation.cloud) {
        _check(epoch);
        await File('${directory.path}/${archive.fileName}').delete();
        await _scanLocal(epoch);
      }
    }
    return archive;
  });

  Future<void> _upload(
    BackupArchive archive,
    int epoch, {
    bool reconcileExisting = false,
  }) async {
    final client = await _client(epoch);
    var entry = await client.upload(
      archive.fileName,
      archive.encode(),
      reconcileExisting: reconcileExisting,
    );
    if (entry.etag == null) {
      // Some servers expose Last-Modified only in PROPFIND, not GET. Record
      // the same fallback fingerprint that future directory checks will see.
      try {
        final observed = await client.list();
        entry = observed.where((e) => e.uri == entry.uri).firstOrNull ?? entry;
      } on WebDavException {
        /* Upload bytes are already verified; listing may be retried. */
      }
    }
    _check(epoch);
    _handled.add(entry.fingerprint);
    await _persist();
    _status = '云端已保存并校验';
  }

  Future<void> upload(BackupArchive archive) =>
      _run((epoch) => _upload(archive, epoch, reconcileExisting: true));

  Future<BackupArchive> download(WebDavEntry entry) => _run((epoch) async {
    final bytes = await (await _client(epoch)).read(entry);
    _check(epoch);
    final archive = BackupArchive.decode(bytes);
    await _saveLocal(archive, epoch);
    _check(epoch);
    _downloadedFrom[archive.id] = entry.fingerprint;
    await _persist();
    await _scanLocal(epoch);
    _status = '已下载到本地，当前数据未改变';
    return archive;
  });

  Future<BackupArchive?> importFile() => _run((epoch) async {
    final bytes = await platform.importFile();
    _check(epoch);
    if (bytes == null) return null;
    final archive = BackupArchive.decode(bytes);
    await _saveLocal(archive, epoch);
    await _scanLocal(epoch);
    return archive;
  });
  Future<bool> exportFile(BackupArchive archive) => _run((epoch) async {
    final result = await platform.exportFile(
      archive.fileName,
      archive.encode(),
    );
    _check(epoch);
    return result;
  });
  Future<void> deleteLocal(BackupArchive archive) => _run((epoch) async {
    _check(epoch);
    final file = File('${directory.path}/${archive.fileName}');
    if (await file.exists()) await file.delete();
    await _scanLocal(epoch);
  });
  Future<void> deleteRemote(WebDavEntry entry) => _run((epoch) async {
    await (await _client(epoch)).delete(entry);
    _check(epoch);
    _remote = _remote.where((e) => e.uri != entry.uri).toList();
  });
  Future<void> ignoreRemote(WebDavEntry entry) => _run((epoch) async {
    _handled.add(entry.fingerprint);
    await _persist();
  });

  Future<RestorePreview> preview(
    BackupArchive archive, {
    required bool replace,
    bool preferArchive = false,
    Set<String>? sections,
  }) => _run(
    (epoch) => store.mutations.run(() async {
      _check(epoch);
      final before = await _capture();
      _check(epoch);
      final groups = BackupMerge.plan(
        before,
        archive.data,
        replace: replace,
        preferArchive: preferArchive,
        sections: sections ?? archive.data.keys.toSet(),
      );
      if (groups.isEmpty) throw const FormatException('请选择存档中存在的内容');
      // Local-only timing remains local, regardless of adopted preferences.
      if (groups['updates'] case final update?) {
        groups['updates'] = {...before['updates']!, ...update};
      }
      return RestorePreview(
        archive: archive,
        before: before,
        groups: groups,
        replace: replace,
        preferArchive: preferArchive,
        generation: _previewGeneration,
      );
    }),
  );

  Future<void> restore(RestorePreview preview) => _run(
    (epoch) => store.mutations.run(() async {
      _check(epoch);
      final current = await _capture();
      if (preview.generation != _previewGeneration ||
          _fingerprint(current) != _fingerprint(preview.before)) {
        throw const AppFailure(FailureKind.cancelled, '当前数据已变化，请重新预览恢复内容');
      }
      _check(epoch);
      await _saveLocal(_archive(current), epoch);
      await store.writeBatch(
        preview.groups,
        canCommit: () => !_disposed && !isPrivate && epoch == _epoch,
      );
      // Load every repository first; synchronous notifications see one complete
      // restored state, never a mix across awaited reads.
      await Future.wait([
        settings.initialize(),
        favorites.initialize(),
        sources.initialize(),
        updates.reloadFromStore(notify: false),
      ]);
      settings.notifyRestored();
      favorites.notifyRestored();
      sources.notifyRestored();
      updates.notifyRestored();
      _previewGeneration++;
      if (_downloadedFrom[preview.archive.id] case final fingerprint?) {
        _handled.add(fingerprint);
        await _persist();
      }
      await _scanLocal(epoch);
      _status = '恢复完成，已保留恢复前的本地存档';
    }),
  );

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    settings.removeListener(_privacyChanged);
    _activeClient?.close();
    unawaited(platform.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
