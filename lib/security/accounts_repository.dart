import 'dart:convert';

import '../models/otp_account.dart';
import 'secure_store.dart';

/// Authenticator accounts, stored as one JSON list in the platform keystore
/// (iOS Keychain / Android Keystore).
///
/// Unreadable data raises an error instead of being cleared: silently
/// deleting 2FA secrets could lock someone out of their accounts.
class AccountsRepository {
  AccountsRepository(this.store);

  final SecureStore store;
  static const _key = 'vaultline.accounts.v1';

  Future<List<OtpAccount>> load() async {
    final raw = await store.read(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return [for (final m in list) OtpAccount.fromJson(Map<String, dynamic>.from(m as Map))];
  }

  Future<void> save(List<OtpAccount> accounts) => store.write(_key, jsonEncode([for (final a in accounts) a.toJson()]));
}
