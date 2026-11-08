import 'dart:typed_data';

/// RFC 4648 Base32, the encoding used for authenticator secrets.
abstract final class Base32 {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Normalises what people paste: drops spaces, hyphens and padding, and
  /// upper-cases. Secrets are often shown as "jbsw y3dp ehpk 3pxp".
  static String normalize(String input) => input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');

  /// True if [input] is a usable secret: valid characters and at least
  /// 80 bits (16 characters), the minimum RFC 4226 allows.
  static bool isValidSecret(String input) {
    final s = normalize(input);
    if (s.length < 16) return false;
    return s.split('').every(_alphabet.contains) && _validLength(s.length);
  }

  // Lengths that can't come from whole bytes are malformed.
  static bool _validLength(int n) => !const {1, 3, 6}.contains(n % 8);

  static Uint8List decode(String input) {
    final s = normalize(input);
    if (!_validLength(s.length)) throw const FormatException('Invalid Base32 length');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in s.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) throw FormatException('Invalid Base32 character: $ch');
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }

  static String encode(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1F]);
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 0x1F]);
    return out.toString();
  }
}
