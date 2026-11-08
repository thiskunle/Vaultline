import '../models/otp_account.dart';
import 'base32.dart';
import 'totp.dart';

/// Why a scanned code couldn't be used, phrased for the person scanning.
class OtpUriException implements Exception {
  const OtpUriException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses `otpauth://totp/...` links, the format inside 2FA setup QR codes
/// (Key URI Format, as used by Google Authenticator and most services):
///
///   otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
///
/// Optional parameters: algorithm (SHA1/SHA256/SHA512), digits (6/8),
/// period (seconds). The `issuer` parameter wins over a label prefix.
abstract final class OtpAuthUri {
  static OtpAccount parse(String raw, {required String id, required DateTime now}) {
    final text = raw.trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('otpauth-migration://')) {
      throw const OtpUriException(
        'That’s a Google Authenticator export code. Vaultline can’t import those yet; '
        'add accounts one at a time with their own setup codes.',
      );
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      throw const OtpUriException('That QR code isn’t a 2FA setup code.');
    }
    if (uri.scheme.toLowerCase() != 'otpauth') {
      throw const OtpUriException('That QR code isn’t a 2FA setup code.');
    }
    final type = uri.host.toLowerCase();
    if (type == 'hotp') {
      throw const OtpUriException('Counter-based (HOTP) codes aren’t supported yet. Only time-based codes are.');
    }
    if (type != 'totp') throw const OtpUriException('That QR code isn’t a 2FA setup code.');

    final q = uri.queryParameters;
    final secret = q['secret'] ?? '';
    if (!Base32.isValidSecret(secret)) {
      throw const OtpUriException('That setup code’s secret key is missing or invalid.');
    }

    // Label is "Issuer:account" or just "account" (already percent-decoded).
    final label = uri.pathSegments.isEmpty ? '' : uri.pathSegments.join('/').trim();
    var labelIssuer = '';
    var name = label;
    final colon = label.indexOf(':');
    if (colon >= 0) {
      labelIssuer = label.substring(0, colon).trim();
      name = label.substring(colon + 1).trim();
    }
    final issuer = (q['issuer']?.trim().isNotEmpty ?? false) ? q['issuer']!.trim() : labelIssuer;

    final algorithm = switch (q['algorithm']?.toUpperCase()) {
      null || 'SHA1' => OtpAlgorithm.sha1,
      'SHA256' => OtpAlgorithm.sha256,
      'SHA512' => OtpAlgorithm.sha512,
      final other => throw OtpUriException('Unsupported algorithm: $other.'),
    };
    final digits = int.tryParse(q['digits'] ?? '6');
    if (digits != 6 && digits != 8) throw const OtpUriException('Only 6- or 8-digit codes are supported.');
    final period = int.tryParse(q['period'] ?? '30');
    if (period == null || period < 10 || period > 300) {
      throw const OtpUriException('That setup code has an invalid refresh period.');
    }

    return OtpAccount(
      id: id,
      issuer: issuer.isEmpty ? (name.isEmpty ? 'New account' : name) : issuer,
      name: issuer.isEmpty ? '' : name,
      secret: Base32.normalize(secret),
      algorithm: algorithm,
      digits: digits!,
      period: period,
      createdAt: now,
    );
  }
}
