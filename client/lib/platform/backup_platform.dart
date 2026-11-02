import 'dart:typed_data';

import 'platform_bridge.dart';

/// Protected credentials and explicit system document exchange on Android.
class BackupPlatform {
  BackupPlatform({PlatformCall? call}) : _call = call ?? callPlatform;

  static const _maxBytes = 16 * 1024 * 1024;
  final PlatformCall _call;

  void _checkKey(String key) {
    if (key.isEmpty ||
        key.length > 128 ||
        RegExp(r'[^A-Za-z0-9_-]').hasMatch(key)) {
      throw ArgumentError('Invalid protected credential slot');
    }
  }

  Future<String> readPassword({String key = 'default'}) async {
    _checkKey(key);
    final value = await _call('backupReadPassword', {
      if (key != 'default') 'key': key,
    });
    if (value is! String) {
      throw const FormatException('Invalid protected credential response');
    }
    return value;
  }

  Future<void> writePassword(String password, {String key = 'default'}) async {
    _checkKey(key);
    await _call('backupWritePassword', {
      'password': password,
      if (key != 'default') 'key': key,
    });
  }

  Future<void> cancel() async {
    await _call('backupCancel', {});
  }

  Future<List<int>?> importFile() async {
    final value = await _call('backupImport', {});
    if (value == null) return null;
    if (value is! List<int> ||
        value.length > _maxBytes ||
        value.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('Invalid backup document response');
    }
    return Uint8List.fromList(value);
  }

  Future<bool> exportFile(String name, List<int> bytes) async {
    if (name.trim().isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name)) {
      throw ArgumentError('Invalid backup document name');
    }
    if (bytes.length > _maxBytes ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Invalid backup document bytes');
    }
    final value = await _call('backupExport', {
      'name': name,
      'bytes': Uint8List.fromList(bytes),
    });
    if (value is! bool) {
      throw const FormatException('Invalid backup document response');
    }
    return value;
  }
}
