import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/models/app_failure.dart';
import 'serial_queue.dart';
import 'snapshot_schema.dart';

class SnapshotStore {
  SnapshotStore(this.directory);
  final Directory directory;
  final _queue = SerialQueue();

  /// Serializes complete repository mutations, separately from file IO.
  final mutations = SerialQueue();
  File _file(String key) {
    if (!RegExp(r'^[a-z_]+$').hasMatch(key)) throw ArgumentError.value(key);
    return File('${directory.path}/$key.json');
  }

  Future<Map<String, Object?>?> _valid(File file, String key) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['data'] is! Map) {
        return null;
      }
      final data = Map<String, Object?>.from(decoded['data'] as Map);
      return SnapshotSchema.accepts(key, data) ? data : null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, Object?>> read(String key) => _queue.run(() async {
    try {
      await _recoverPending();
      final current = _file(key), backup = File('${_file(key).path}.bak');
      final data = await _valid(current, key) ?? await _valid(backup, key);
      if (data != null) return data;
      if (await current.exists() || await backup.exists()) {
        throw const AppFailure(FailureKind.storage, '本地数据损坏，原文件已保留');
      }
      return <String, Object?>{};
    } on FileSystemException catch (e) {
      throw AppFailure(FailureKind.storage, '无法读取本地数据', e.message);
    }
  });
  Future<void> write(String key, Map<String, Object?> data) =>
      _queue.run(() async {
        await _recoverPending();
        await _write(key, data);
      });

  Future<void> _write(String key, Map<String, Object?> data) async {
    try {
      await directory.create(recursive: true);
      final current = _file(key), temp = File('${_file(key).path}.tmp');
      await temp.writeAsString(
        jsonEncode({'version': 1, 'data': data}),
        flush: true,
      );
      if (await _valid(current, key) != null) {
        final nextBackup = File('${current.path}.bak.tmp');
        await nextBackup.writeAsBytes(await current.readAsBytes(), flush: true);
        await _replace(nextBackup, File('${current.path}.bak'));
      }
      await _replace(temp, current);
    } on FileSystemException catch (e) {
      throw AppFailure(FailureKind.storage, '无法保存本地数据，原记录已保留', e.message);
    }
  }

  File get _journal => File('${directory.path}/restore_transaction.json');
  File get _commit => File('${directory.path}/restore_transaction.commit');
  static const _restoreKeys = {'settings', 'favorites', 'sources', 'updates'};

  Future<void> recover() => _queue.run(_recoverPending);

  Future<void> _writeJournal(Map<String, Object?> journal) async {
    await directory.create(recursive: true);
    final next = File('${_journal.path}.tmp');
    await next.writeAsString(jsonEncode(journal), flush: true);
    await _replace(next, _journal);
  }

  Future<void> _applyGroups(Map<String, Object?> groups) async {
    for (final entry in groups.entries) {
      if (entry.value == null) {
        for (final file in [
          _file(entry.key),
          File('${_file(entry.key).path}.bak'),
        ]) {
          if (await file.exists()) await file.delete();
        }
      } else {
        await _write(entry.key, Map<String, Object?>.from(entry.value as Map));
      }
    }
  }

  Future<void> _recoverPending() async {
    if (!await _journal.exists()) {
      if (await _commit.exists()) await _commit.delete();
      return;
    }
    try {
      if (await _journal.length() > 64 * 1024 * 1024) {
        throw const FormatException('Oversize transaction');
      }
      final raw = await _journal.readAsString();
      final decoded = jsonDecode(raw) as Map;
      if (decoded['version'] != 1 || decoded['committed'] is! bool) {
        throw const FormatException('Invalid transaction');
      }
      final before = Map<String, Object?>.from(decoded['before'] as Map);
      final after = Map<String, Object?>.from(decoded['after'] as Map);
      if (before.isEmpty ||
          before.length != after.length ||
          !before.keys.every(after.containsKey)) {
        throw const FormatException('Invalid transaction groups');
      }
      for (final group in [before, after]) {
        for (final entry in group.entries) {
          if (!_restoreKeys.contains(entry.key) ||
              (entry.value == null && identical(group, after)) ||
              (entry.value != null &&
                  !SnapshotSchema.accepts(
                    entry.key,
                    Map<String, Object?>.from(entry.value as Map),
                  ))) {
            throw const FormatException('Invalid transaction payload');
          }
        }
      }
      final committed =
          decoded['committed'] == true ||
          (await _commit.exists() &&
              await _commit.readAsString() ==
                  sha256.convert(utf8.encode(raw)).toString());
      await _applyGroups(committed ? after : before);
      await _journal.delete();
      if (await _commit.exists()) await _commit.delete();
    } catch (_) {
      throw const AppFailure(FailureKind.storage, '恢复事务未完成，原文件已保留，请重新打开应用重试');
    }
  }

  Future<void> writeBatch(
    Map<String, Map<String, Object?>> groups, {
    bool Function()? canCommit,
  }) => _queue.run(() async {
    await _recoverPending();
    if (groups.isEmpty ||
        groups.entries.any(
          (e) =>
              !_restoreKeys.contains(e.key) ||
              !SnapshotSchema.accepts(e.key, e.value),
        )) {
      throw const AppFailure(FailureKind.malformed, '恢复内容无效，未修改数据');
    }
    void check() {
      if (canCommit != null && !canCommit()) {
        throw const AppFailure(FailureKind.cancelled, '恢复已取消');
      }
    }

    check();
    final before = <String, Object?>{};
    for (final key in groups.keys) {
      before[key] =
          await _valid(_file(key), key) ??
          await _valid(File('${_file(key).path}.bak'), key);
      if (before[key] == null &&
          (await _file(key).exists() ||
              await File('${_file(key).path}.bak').exists())) {
        throw const AppFailure(FailureKind.storage, '原数据损坏，已保留文件，未执行恢复');
      }
    }
    final journal = <String, Object?>{
      'version': 1,
      'committed': false,
      'before': before,
      'after': groups,
    };
    if (utf8.encode(jsonEncode(journal)).length > 64 * 1024 * 1024) {
      throw const AppFailure(FailureKind.storage, '恢复数据过大，未修改原记录');
    }
    await _writeJournal(journal);
    try {
      for (final entry in groups.entries) {
        check();
        await _write(entry.key, entry.value);
      }
      check();
      final marker = File('${_commit.path}.tmp');
      await marker.writeAsString(
        sha256.convert(utf8.encode(jsonEncode(journal))).toString(),
        flush: true,
      );
      check();
      // Never replace/delete the prepared journal to mark a commit: Windows
      // rename-over-existing needs a deletion gap, unsafe for multiple keys.
      await marker.rename(_commit.path);
    } catch (_) {
      await _recoverPending();
      rethrow;
    }
    // The committed journal is authoritative if cleanup is interrupted.
    try {
      await _journal.delete();
      if (await _commit.exists()) await _commit.delete();
    } on FileSystemException {
      /* Recovered on next IO. */
    }
  });
  static Future<void> _replace(File from, File to) async {
    // A valid backup already exists before replacing the current file.
    if (Platform.isWindows && await to.exists()) await to.delete();
    await from.rename(to.path);
  }
}
