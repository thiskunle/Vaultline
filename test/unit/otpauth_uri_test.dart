import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/models/otp_account.dart';
import 'package:vaultline/otp/otpauth_uri.dart';
import 'package:vaultline/otp/totp.dart';

OtpAccount parse(String uri) => OtpAuthUri.parse(uri, id: 'x', now: DateTime.utc(2026, 11, 8));

Matcher rejects(String messageFragment) =>
    throwsA(isA<OtpUriException>().having((e) => e.message, 'message', contains(messageFragment)));

void main() {
  test('the Key URI Format example', () {
    final a = parse('otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example');
    expect(a.issuer, 'Example');
    expect(a.name, 'alice@google.com');
    expect(a.secret, 'JBSWY3DPEHPK3PXP');
    expect((a.algorithm, a.digits, a.period), (OtpAlgorithm.sha1, 6, 30));
  });

  test('percent-encoded label with an encoded colon and spaces', () {
    final a = parse('otpauth://totp/ACME%20Co%3Ajohn.doe%40email.com?secret=JBSWY3DPEHPK3PXP');
    expect(a.issuer, 'ACME Co');
    expect(a.name, 'john.doe@email.com');
  });

  test('the issuer parameter wins over the label prefix', () {
    final a = parse('otpauth://totp/Old%20Name:ada?secret=JBSWY3DPEHPK3PXP&issuer=New+Name');
    expect(a.issuer, 'New Name');
    expect(a.name, 'ada');
  });

  test('issuer only in the parameter, or only an account in the label', () {
    expect(parse('otpauth://totp/ada@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub').issuer, 'GitHub');
    final noIssuer = parse('otpauth://totp/ada@example.com?secret=JBSWY3DPEHPK3PXP');
    expect(noIssuer.issuer, 'ada@example.com');
    expect(noIssuer.name, '');
    expect(parse('otpauth://totp/?secret=JBSWY3DPEHPK3PXP').issuer, 'New account');
  });

  test('optional parameters, lowercase scheme parts and a spaced lowercase secret', () {
    final a = parse(
      'OTPAUTH://TOTP/Bank:ada?secret=gezd%20gnbv%20gy3t%20qojq%20gezd%20gnbv%20gy3t%20qojq'
      '&algorithm=sha256&digits=8&period=60',
    );
    expect(a.secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
    expect((a.algorithm, a.digits, a.period), (OtpAlgorithm.sha256, 8, 60));
  });

  test('parsed accounts produce the RFC 6238 codes', () {
    final a = parse('otpauth://totp/RFC:test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8');
    expect(a.codeAt(DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)), '94287082');
  });

  group('rejects, with a clear reason', () {
    test('not a 2FA code', () {
      expect(() => parse('https://example.com'), rejects('isn’t a 2FA setup code'));
      expect(() => parse('hello'), rejects('isn’t a 2FA setup code'));
      expect(() => parse('otpauth://foo/x?secret=JBSWY3DPEHPK3PXP'), rejects('isn’t a 2FA setup code'));
    });

    test('HOTP and Google Authenticator exports', () {
      expect(() => parse('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=0'), rejects('HOTP'));
      expect(() => parse('otpauth-migration://offline?data=abc'), rejects('Google Authenticator export'));
    });

    test('missing or invalid secrets', () {
      expect(() => parse('otpauth://totp/x?issuer=A'), rejects('secret key'));
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DP'), rejects('secret key'));
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PX1'), rejects('secret key'));
    });

    test('unsupported options', () {
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&algorithm=MD5'), rejects('MD5'));
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=7'), rejects('6- or 8-digit'));
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=0'), rejects('refresh period'));
      expect(() => parse('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&period=abc'), rejects('refresh period'));
    });
  });
}
