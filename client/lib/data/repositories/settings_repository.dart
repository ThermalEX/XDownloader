import 'package:flutter/foundation.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/app_failure.dart';
import '../../core/security/privacy_password.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this.store, {PrivacyPasswords? passwords})
    : _passwords = passwords ?? PrivacyPasswords();
  final SnapshotStore store;
  final PrivacyPasswords _passwords;
  final _queue = SerialQueue();
  AppSettings _value = const AppSettings();
  AppSettings get value => _value;
  Future<void> initialize() async {
    _value = AppSettings.fromJson(await store.read('settings'));
  }

  Future<void> update(AppSettings next) => edit((_) => next);
  Future<void> edit(AppSettings Function(AppSettings current) transform) =>
      _queue.run(() async {
        final next = transform(_value);
        if (next.privacyPasswordHash != _value.privacyPasswordHash ||
            (_value.privacyPasswordHash.isNotEmpty &&
                _value.privacyMode &&
                !next.privacyMode)) {
          throw const AppFailure(FailureKind.cancelled, '请先验证隐私密码');
        }
        await _write(next);
      });

  Future<void> _write(AppSettings next) async {
    await store.write('settings', next.toJson());
    _value = next;
    notifyListeners();
  }

  Future<void> _verify(String password, String hash) async {
    if (hash.isNotEmpty && !await _passwords.matches(password, hash)) {
      throw const AppFailure(FailureKind.cancelled, '密码不正确');
    }
  }

  void _checkCurrent(String hash) {
    if (_value.privacyPasswordHash != hash) {
      throw const AppFailure(FailureKind.cancelled, '隐私密码已更改，请重试');
    }
  }

  Future<void> setPrivacyMode(bool enabled, {String password = ''}) async {
    if (enabled) return edit((s) => s.copyWith(privacyMode: true));
    if (!await tryUnlockPrivacy(password)) {
      throw const AppFailure(FailureKind.cancelled, '密码不正确');
    }
  }

  /// Wrong/partial PINs are silent. A late result must not unlock after the
  /// caller edited the input or left the unlock screen.
  Future<bool> tryUnlockPrivacy(
    String password, {
    bool Function()? canCommit,
  }) async {
    final hash = _value.privacyPasswordHash;
    if (hash.isNotEmpty && !await _passwords.matches(password, hash)) {
      return false;
    }
    return _queue.run(() async {
      _checkCurrent(hash);
      if (canCommit != null && !canCommit()) return false;
      await _write(_value.copyWith(privacyMode: false));
      return true;
    });
  }

  Future<void> setPrivacyPassword(
    String? password, {
    String currentPassword = '',
  }) async {
    if (password != null && PrivacyPasswords.validate(password) != null) {
      throw AppFailure(
        FailureKind.cancelled,
        PrivacyPasswords.validate(password)!,
      );
    }
    final previous = _value.privacyPasswordHash;
    await _verify(currentPassword, previous);
    final hash = password == null ? '' : await _passwords.hash(password);
    await _queue.run(() async {
      _checkCurrent(previous);
      await _write(_value.copyWith(privacyPasswordHash: hash));
    });
  }
}
