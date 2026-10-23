import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/platform/android_privacy_passwords.dart';

void main() {
  // Independent Python hashlib vectors, also checked against the compiled
  // Kotlin provider on the host JVM. Existing persisted descriptors are kept.
  const vectors = {
    '0123': 'dc496ed5815692367dfff09d531b5f961ea3042c45f495187f6d8d3be476ef41',
    '01234': 'a6f717c261ee48e131eeddbc672726dedc5b2e7873281cd453401399093f736a',
    '012345':
        '51394b56fe604a83204431d587a8c2d99c5cd735ff85957b79d7fbebfb585743',
  };
  for (final entry in vectors.entries) {
    test(
      'native ${entry.key.length} digit PIN verifier preserves existing snapshots',
      () async {
        final calls = <String>[];
        final passwords = AndroidPrivacyPasswords(
          call: (method, args) async {
            expect(method, 'privacyDerive');
            expect(args['salt'], isA<Uint8List>());
            expect(args['salt'], orderedEquals(List.generate(16, (i) => i)));
            calls.add(args['password'] as String);
            return args['password'] == entry.key ? entry.value : '00' * 32;
          },
        );
        final hash =
            'pbkdf2-sha256:600000:000102030405060708090a0b0c0d0e0f:${entry.value}';
        expect(await passwords.matches(entry.key, hash), isTrue);
        expect(await passwords.matches('9999', hash), isFalse);
        expect(calls, [entry.key, '9999']);
      },
    );
  }
  test(
    'malformed native result fails closed without a slow fallback',
    () async {
      final passwords = AndroidPrivacyPasswords(
        call: (_, args) async => 'invalid',
      );
      await expectLater(passwords.hash('01234'), throwsFormatException);
    },
  );
  test(
    'native provider failure propagates without storing a password',
    () async {
      final passwords = AndroidPrivacyPasswords(
        call: (_, args) async => throw PlatformException(code: 'privacy'),
      );
      await expectLater(
        passwords.hash('01234'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
