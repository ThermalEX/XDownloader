import 'dart:io';
import 'dart:convert';

import '../../core/models/app_failure.dart';
import 'serial_queue.dart';
import 'snapshot_schema.dart';

class SnapshotStore {
  SnapshotStore(this.directory);
  final Directory directory;
  final _queue = SerialQueue();
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
        try {
          await directory.create(recursive: true);
          final current = _file(key), temp = File('${_file(key).path}.tmp');
          await temp.writeAsString(
            jsonEncode({'version': 1, 'data': data}),
            flush: true,
          );
          if (await _valid(current, key) != null) {
            final nextBackup = File('${current.path}.bak.tmp');
            await nextBackup.writeAsBytes(
              await current.readAsBytes(),
              flush: true,
            );
            await _replace(nextBackup, File('${current.path}.bak'));
          }
          await _replace(temp, current);
        } on FileSystemException catch (e) {
          throw AppFailure(FailureKind.storage, '无法保存本地数据，原记录已保留', e.message);
        }
      });
  static Future<void> _replace(File from, File to) async {
    // A valid backup already exists before replacing the current file.
    if (Platform.isWindows && await to.exists()) await to.delete();
    await from.rename(to.path);
  }
}
