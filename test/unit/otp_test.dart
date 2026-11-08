import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/models/otp_account.dart';
import 'package:vaultline/otp/base32.dart';
import 'package:vaultline/otp/totp.dart';

void main() {
  group('Base32 (RFC 4648)', () {
    test('RFC 4648 §10 test vectors', () {
      const vectors = {
        '': '',
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };
      vectors.forEach((plain, encoded) {
        expect(Base32.encode(utf8.encode(plain)), encoded, reason: plain);
        expect(utf8.decode(Base32.decode(encoded)), plain, reason: encoded);
      });
    });

    test('accepts the way secrets are usually shown', () {
      final a = Base32.decode('JBSWY3DPEHPK3PXP');
      expect(Base32.decode('jbsw y3dp ehpk 3pxp'), a);
      expect(Base32.decode('JBSW-Y3DP-EHPK-3PXP'), a);
      expect(Base32.decode('MZXW6YTBOI======'), utf8.encode('foobar'));
    });

    test('rejects bad characters, bad lengths and too-short secrets', () {
      expect(Base32.isValidSecret('JBSWY3DPEHPK3PXP'), isTrue);
      expect(Base32.isValidSecret('JBSWY3DPEHPK3PX1'), isFalse, reason: '1 is not Base32');
      expect(Base32.isValidSecret('JBSWY3DPEHPK3PX'), isFalse, reason: 'invalid length');
      expect(Base32.isValidSecret('JBSWY3DP'), isFalse, reason: 'under 80 bits');
      expect(() => Base32.decode('ABC'), throwsFormatException);
    });
  });

  group('HOTP (RFC 4226 Appendix D)', () {
    test('counter 0..9', () {
      final key = utf8.encode('12345678901234567890');
      const expected = [
        '755224',
        '287082',
        '359152',
        '969429',
        '338314',
        '254676',
        '287922',
        '162583',
        '399871',
        '520489',
      ];
      for (var c = 0; c < 10; c++) {
        expect(Otp.hotp(key, c), expected[c], reason: 'counter $c');
      }
    });
  });

  group('TOTP (RFC 6238 Appendix B)', () {
    final keys = {
      OtpAlgorithm.sha1: utf8.encode('12345678901234567890'),
      OtpAlgorithm.sha256: utf8.encode('12345678901234567890123456789012'),
      OtpAlgorithm.sha512: utf8.encode('1234567890123456789012345678901234567890123456789012345678901234'),
    };
    const table = {
      59: ['94287082', '46119246', '90693936'],
      1111111109: ['07081804', '68084774', '25091201'],
      1111111111: ['14050471', '67062674', '99943326'],
      1234567890: ['89005924', '91819424', '93441116'],
      2000000000: ['69279037', '90698825', '38618901'],
      20000000000: ['65353130', '77737706', '47863826'],
    };

    table.forEach((seconds, codes) {
      test('T = $seconds', () {
        final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        for (final (i, alg) in OtpAlgorithm.values.indexed) {
          expect(Otp.totp(keys[alg]!, time, digits: 8, algorithm: alg), codes[i], reason: '${alg.label} @ $seconds');
        }
      });
    });

    test('countdown helpers', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000 + 500, isUtc: true);
      // 1111111109 % 30 = 29 → 1 s left, almost the whole period elapsed.
      expect(Otp.secondsLeft(t), 1);
      expect(Otp.progress(t), closeTo(29.5 / 30, 1e-9));
      expect(Otp.counterAt(t), 37037036);
    });
  });

  test('account JSON round trip and code', () {
    final a = OtpAccount(
      id: 'a1',
      issuer: 'GitHub',
      name: 'ada@example.com',
      secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', // Base32 of "12345678901234567890"
      digits: 8,
      createdAt: DateTime.utc(2026, 11, 8),
    );
    final back = OtpAccount.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    expect(back.toJson(), a.toJson());
    expect(back.codeAt(DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)), '94287082');
  });
}
