import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xdownloader/core/security/privacy_password.dart';

/// Cheap deterministic verifier for interaction/transaction tests only.
class TestPrivacyPasswords extends PrivacyPasswords {
  Completer<void>? verifying;
  @override
  Future<String> hash(String password) async =>
      'pbkdf2-sha256:600000:${'01' * 16}:${sha256.convert(utf8.encode(password))}';
  @override
  Future<bool> matches(String password, String encoded) async {
    await verifying?.future;
    return encoded == await hash(password);
  }
}
