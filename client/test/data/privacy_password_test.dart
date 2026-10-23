import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/security/privacy_password.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/storage/snapshot_schema.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/app_fixture.dart';
import '../support/fake_privacy_passwords.dart';

void main() {
  test('only four to six ASCII digits can be configured as a PIN', () {
    for (final invalid in ['123', '1234567', 'abcdef', '１２３４５６', '12 456']) {
      expect(PrivacyPasswords.validate(invalid), isNotNull);
    }
    for (final valid in ['0001', '01234', '000123']) {
      expect(PrivacyPasswords.validate(valid), isNull);
    }
  });

  test('PBKDF2 SHA256 matches independently generated test vectors', () {
    expect(
      pbkdf2Sha256('password', utf8.encode('salt'), 1),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      pbkdf2Sha256('password', utf8.encode('salt'), 2),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('real password hashes are salted and verify six digit PINs off the UI isolate', () async {
    final passwords = PrivacyPasswords();
    final hash = await passwords.hash('123456');
    expect(PrivacyPasswords.validHash(hash), isTrue);
    expect(hash, isNot(contains('123456')));
    expect(await passwords.matches('123456', hash), isTrue);
    expect(await passwords.matches('wrong', hash), isFalse);
    expect(await passwords.hash('123456'), isNot(hash));
  });

  test(
    'password field is optional but malformed or weakened hashes are rejected',
    () {
      expect(AppSettings.fromJson({}).privacyPasswordHash, '');
      for (final value in [
        'plain-password',
        'pbkdf2-sha256:1:${'01' * 16}:${'00' * 32}',
        123,
      ]) {
        expect(
          SnapshotSchema.accepts('settings', {'privacyPasswordHash': value}),
          isFalse,
        );
      }
    },
  );

  test(
    'no password unlocks directly; configured password guards all mutations',
    () async {
      final store = MemorySnapshotStore();
      final settings = SettingsRepository(
        store,
        passwords: TestPrivacyPasswords(),
      );
      addTearDown(settings.dispose);
      await settings.initialize();
      await settings.setPrivacyMode(true);
      await settings.setPrivacyMode(false);
      expect(settings.value.privacyMode, isFalse);
      await settings.setPrivacyPassword('123456');
      await settings.setPrivacyMode(true);
      await expectLater(
        settings.setPrivacyMode(false, password: 'wrong'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        settings.edit((s) => s.copyWith(privacyMode: false)),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        settings.edit((s) => s.copyWith(privacyPasswordHash: '')),
        throwsA(isA<AppFailure>()),
      );
      expect(settings.value.privacyMode, isTrue);
      await expectLater(
        settings.setPrivacyPassword(null, currentPassword: 'wrong'),
        throwsA(isA<AppFailure>()),
      );
      await settings.edit((s) => s.copyWith(seedColor: 42));
      await settings.setPrivacyMode(false, password: '123456');
      expect(settings.value.privacyMode, isFalse);
      expect(settings.value.seedColor, 42);
      final restored = SettingsRepository(
        store,
        passwords: TestPrivacyPasswords(),
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(
        restored.value.privacyPasswordHash,
        settings.value.privacyPasswordHash,
      );
      await restored.setPrivacyPassword(null, currentPassword: '123456');
      expect(restored.value.privacyPasswordHash, '');
      await restored.setPrivacyMode(true);
      await restored.setPrivacyMode(false);
    },
  );

  test(
    'stale password verification cannot unlock after password changes',
    () async {
      final passwords = TestPrivacyPasswords();
      final settings = SettingsRepository(
        MemorySnapshotStore(),
        passwords: passwords,
      );
      addTearDown(settings.dispose);
      await settings.initialize();
      await settings.setPrivacyPassword('123456');
      await settings.setPrivacyMode(true);
      final gate = passwords.verifying = Completer<void>();
      final unlocking = settings.setPrivacyMode(false, password: '123456');
      passwords.verifying = null;
      await settings.setPrivacyPassword('567890', currentPassword: '123456');
      gate.complete();
      await expectLater(unlocking, throwsA(isA<AppFailure>()));
      expect(settings.value.privacyMode, isTrue);
    },
  );

  test('a valid but outdated input cannot commit a privacy unlock', () async {
    final passwords = TestPrivacyPasswords();
    final settings = SettingsRepository(
      MemorySnapshotStore(),
      passwords: passwords,
    );
    addTearDown(settings.dispose);
    await settings.initialize();
    await settings.setPrivacyPassword('01234');
    await settings.setPrivacyMode(true);
    var current = true;
    final gate = passwords.verifying = Completer<void>();
    final unlocking = settings.tryUnlockPrivacy(
      '01234',
      canCommit: () => current,
    );
    current = false;
    gate.complete();
    expect(await unlocking, isFalse);
    expect(settings.value.privacyMode, isTrue);
    expect(await settings.tryUnlockPrivacy('9999'), isFalse);
    expect(settings.value.privacyMode, isTrue);
    expect(await settings.tryUnlockPrivacy('01234'), isTrue);
  });

  test(
    'real disk backup preserves password through damaged known field',
    () async {
      final root = await Directory.systemTemp.createTemp('xdl-password-');
      try {
        final store = SnapshotStore(root);
        final settings = SettingsRepository(
          store,
          passwords: TestPrivacyPasswords(),
        );
        await settings.initialize();
        await settings.setPrivacyPassword('123456');
        await settings.setPrivacyMode(true);
        await settings.edit((s) => s.copyWith(autoClipboard: false));
        await File('${root.path}/settings.json').writeAsString(
          jsonEncode({
            'version': 1,
            'data': {'privacyPasswordHash': 'corrupt', 'privacyMode': false},
          }),
        );
        final restored = SettingsRepository(
          store,
          passwords: TestPrivacyPasswords(),
        );
        await restored.initialize();
        expect(
          restored.value.privacyPasswordHash,
          settings.value.privacyPasswordHash,
        );
        expect(restored.value.privacyMode, isTrue);
        restored.dispose();
        settings.dispose();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
