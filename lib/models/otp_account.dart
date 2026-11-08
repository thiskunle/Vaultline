import 'package:flutter/foundation.dart';

import '../otp/base32.dart';
import '../otp/totp.dart';

/// One authenticator entry. [secret] is the Base32 key from the service.
@immutable
class OtpAccount {
  const OtpAccount({
    required this.id,
    required this.issuer,
    required this.name,
    required this.secret,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    required this.createdAt,
  });

  final String id;

  /// Service, e.g. "GitHub".
  final String issuer;

  /// Account at that service, e.g. "ada@example.com".
  final String name;
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;
  final DateTime createdAt;

  Uint8List get key => Base32.decode(secret);

  String codeAt(DateTime time) => Otp.totp(key, time, digits: digits, period: period, algorithm: algorithm);

  OtpAccount copyWith({String? issuer, String? name}) => OtpAccount(
    id: id,
    issuer: issuer ?? this.issuer,
    name: name ?? this.name,
    secret: secret,
    algorithm: algorithm,
    digits: digits,
    period: period,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'issuer': issuer,
    'name': name,
    'secret': secret,
    'algorithm': algorithm.label,
    'digits': digits,
    'period': period,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OtpAccount.fromJson(Map<String, dynamic> j) => OtpAccount(
    id: j['id'] as String,
    issuer: j['issuer'] as String,
    name: j['name'] as String,
    secret: j['secret'] as String,
    algorithm: OtpAlgorithm.parse(j['algorithm'] as String? ?? 'SHA1'),
    digits: j['digits'] as int? ?? 6,
    period: j['period'] as int? ?? 30,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}
