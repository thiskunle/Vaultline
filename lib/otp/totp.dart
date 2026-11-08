import 'dart:typed_data';

// Prefixed: the enum's own values are named sha1/sha256/sha512.
import 'package:crypto/crypto.dart' as crypto;

enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.label);
  final String label;

  crypto.Hash get hash => switch (this) {
    OtpAlgorithm.sha1 => crypto.sha1,
    OtpAlgorithm.sha256 => crypto.sha256,
    OtpAlgorithm.sha512 => crypto.sha512,
  };

  static OtpAlgorithm parse(String s) =>
      OtpAlgorithm.values.firstWhere((a) => a.label == s.toUpperCase(), orElse: () => OtpAlgorithm.sha1);
}

/// HOTP (RFC 4226) and TOTP (RFC 6238).
abstract final class Otp {
  /// HMAC-based one-time password for [counter].
  static String hotp(List<int> key, int counter, {int digits = 6, OtpAlgorithm algorithm = OtpAlgorithm.sha1}) {
    // 8-byte big-endian counter, written as two 32-bit halves because
    // setUint64 isn't available on the web.
    final msg = ByteData(8)
      ..setUint32(0, counter ~/ 0x100000000)
      ..setUint32(4, counter % 0x100000000);
    final mac = crypto.Hmac(algorithm.hash, key).convert(msg.buffer.asUint8List()).bytes;
    // Dynamic truncation (RFC 4226 §5.3).
    final offset = mac.last & 0x0F;
    final binary =
        ((mac[offset] & 0x7F) << 24) |
        ((mac[offset + 1] & 0xFF) << 16) |
        ((mac[offset + 2] & 0xFF) << 8) |
        (mac[offset + 3] & 0xFF);
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (binary % mod).toString().padLeft(digits, '0');
  }

  /// Time step for [time] (Unix time / period, rounded down).
  static int counterAt(DateTime time, {int period = 30}) => time.millisecondsSinceEpoch ~/ 1000 ~/ period;

  static String totp(
    List<int> key,
    DateTime time, {
    int digits = 6,
    int period = 30,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) => hotp(
    key,
    counterAt(time, period: period),
    digits: digits,
    algorithm: algorithm,
  );

  /// Fraction of the current period that has elapsed, 0..1 (for countdown
  /// rings).
  static double progress(DateTime time, {int period = 30}) {
    final ms = time.millisecondsSinceEpoch % (period * 1000);
    return ms / (period * 1000);
  }

  /// Whole seconds until the code changes.
  static int secondsLeft(DateTime time, {int period = 30}) => period - (time.millisecondsSinceEpoch ~/ 1000) % period;
}
