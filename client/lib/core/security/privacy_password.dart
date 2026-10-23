import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, versioned local password verifier; no plaintext is persisted.
typedef PrivacyKeyDeriver = Future<String> Function(
  String password,
  List<int> salt,
);

class PrivacyPasswords {
  PrivacyPasswords({PrivacyKeyDeriver? derive})
    : _derive = derive ?? _deriveInIsolate;
  final PrivacyKeyDeriver _derive;
  static Future<String> _deriveInIsolate(String password, List<int> salt) =>
      Isolate.run(() => pbkdf2Sha256(password, salt, iterations));
  static const iterations = 600000;
  static final _format = RegExp(
    r'^pbkdf2-sha256:600000:[0-9a-f]{32}:[0-9a-f]{64}$',
  );
  static bool validHash(String value) =>
      value.isEmpty || _format.hasMatch(value);
  static String? validate(String password) =>
      !RegExp(r'^[0-9]{4,6}$').hasMatch(password) ? 'PIN 需要 4–6 位数字' : null;

  Future<String> hash(String password) async {
    if (validate(password) != null) throw ArgumentError(validate(password));
    final random = Random.secure();
    final salt = List.generate(16, (_) => random.nextInt(256));
    final digest = await _derive(password, salt);
    return 'pbkdf2-sha256:$iterations:${_hex(salt)}:$digest';
  }

  Future<bool> matches(String password, String encoded) async {
    if (encoded.isEmpty) return true;
    if (!validHash(encoded) || validate(password) != null) return false;
    final fields = encoded.split(':');
    final salt = [
      for (var i = 0; i < fields[2].length; i += 2)
        int.parse(fields[2].substring(i, i + 2), radix: 16),
    ];
    final actual = await _derive(password, salt);
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ fields[3].codeUnitAt(i);
    }
    return difference == 0;
  }
}

// PBKDF2-HMAC-SHA256, one 32-byte block. The cost follows OWASP's PBKDF2
// guidance; execute it on a worker isolate, never during a widget build.
String pbkdf2Sha256(String password, List<int> salt, int iterations) {
  if (iterations < 1) throw ArgumentError.value(iterations);
  final encoded = utf8.encode(password);
  final key = encoded.length > 64 ? sha256.convert(encoded).bytes : encoded;
  final hmac = Hmac(sha256, key);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final output = List<int>.from(block);
  for (var round = 1; round < iterations; round++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < output.length; i++) {
      output[i] ^= block[i];
    }
  }
  return _hex(output);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
