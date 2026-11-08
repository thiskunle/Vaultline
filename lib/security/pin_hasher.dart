import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A stored PIN verifier: never the PIN itself, only a salted PBKDF2 hash.
class PinRecord {
  const PinRecord({required this.salt, required this.hash, required this.iterations});

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;

  static const version = 1;

  String encode() => jsonEncode({
    'v': version,
    'alg': 'pbkdf2-hmac-sha256',
    'iter': iterations,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
  });

  static PinRecord decode(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (m['v'] != version || m['alg'] != 'pbkdf2-hmac-sha256') {
      throw const FormatException('Unsupported PIN record');
    }
    return PinRecord(
      salt: base64Decode(m['salt'] as String),
      hash: base64Decode(m['hash'] as String),
      iterations: m['iter'] as int,
    );
  }
}

/// Hashes and verifies PINs with PBKDF2-HMAC-SHA256.
///
/// Work runs on a background isolate so the UI never stutters. The hash is
/// stored in the platform keystore (Keychain / Android Keystore), so offline
/// guessing would first require compromising the device; the lockout policy
/// limits online guessing.
class PinHasher {
  const PinHasher({this.iterations = defaultIterations, this.inBackground = true});

  /// Tuned to stay well under a second on current phones in release mode.
  static const defaultIterations = 150000;

  final int iterations;

  /// Off in widget tests, whose fake clock can't receive isolate results.
  final bool inBackground;

  Future<PinRecord> create(String pin) async {
    final salt = _randomBytes(16);
    final hash = await _run(pin, salt, iterations);
    return PinRecord(salt: salt, hash: hash, iterations: iterations);
  }

  Future<bool> verify(String pin, PinRecord record) async {
    final candidate = await _run(pin, record.salt, record.iterations);
    return constantTimeEquals(candidate, record.hash);
  }

  Future<Uint8List> _run(String pin, Uint8List salt, int iterations) =>
      inBackground ? Isolate.run(() => _derive(pin, salt, iterations)) : _derive(pin, salt, iterations);

  static Future<Uint8List> _derive(String pin, Uint8List salt, int iterations) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  static Uint8List _randomBytes(int length) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
  }
}

/// Compares in time that depends only on length, not on where bytes differ.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
