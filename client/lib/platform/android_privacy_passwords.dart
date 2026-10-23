import 'dart:typed_data';

import '../core/security/privacy_password.dart';
import 'platform_bridge.dart';

/// Same persisted PBKDF2 verifier, using Android's native crypto provider.
class AndroidPrivacyPasswords extends PrivacyPasswords {
  AndroidPrivacyPasswords({PlatformCall? call})
    : super(
        derive: (password, salt) async {
          final result = await (call ?? callPlatform)('privacyDerive', {
            'password': password,
            'salt': Uint8List.fromList(salt),
          });
          if (result is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) {
            throw const FormatException('Invalid native password verifier');
          }
          return result;
        },
      );
}
