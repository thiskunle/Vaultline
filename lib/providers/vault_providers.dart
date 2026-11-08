import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/otp_account.dart';
import '../security/accounts_repository.dart';
import '../security/biometrics.dart';
import '../security/lock_service.dart';
import '../security/pin_hasher.dart';
import '../security/secure_store.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => const PlatformSecureStore());
final biometricsProvider = Provider<Biometrics>((ref) => PlatformBiometrics());
final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

final lockServiceProvider = Provider<LockService>(
  (ref) => LockService(store: ref.watch(secureStoreProvider), hasher: ref.watch(pinHasherProvider)),
);

/// What biometric the device offers right now (none if not enrolled).
final biometricKindProvider = FutureProvider<BiometricKind>((ref) => ref.watch(biometricsProvider).available());

enum VaultStatus { needsSetup, locked, unlocked }

/// Single source of truth for whether the vault is open. Navigation follows
/// it, so there is no route into the vault that skips the lock.
class VaultController extends AsyncNotifier<VaultStatus> {
  @override
  Future<VaultStatus> build() async =>
      await ref.read(lockServiceProvider).hasPin() ? VaultStatus.locked : VaultStatus.needsSetup;

  /// Called by the lock/setup screens once the door has finished opening.
  void markUnlocked() => state = const AsyncData(VaultStatus.unlocked);

  void lock() => state = const AsyncData(VaultStatus.locked);
}

final vaultControllerProvider = AsyncNotifierProvider<VaultController, VaultStatus>(VaultController.new);

/// Whether the user turned on biometric unlock.
class BiometricEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(lockServiceProvider).biometricEnabled();

  Future<void> set(bool on) async {
    await ref.read(lockServiceProvider).setBiometricEnabled(on);
    state = AsyncData(on);
  }
}

final biometricEnabledProvider = AsyncNotifierProvider<BiometricEnabled, bool>(BiometricEnabled.new);

/// Current time; overridden in tests to make codes deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final accountsRepositoryProvider = Provider((ref) => AccountsRepository(ref.watch(secureStoreProvider)));

/// The authenticator accounts, oldest first.
class AccountsController extends AsyncNotifier<List<OtpAccount>> {
  @override
  Future<List<OtpAccount>> build() => ref.read(accountsRepositoryProvider).load();

  /// Adds an account. Returns false if the same secret is already saved.
  Future<bool> add(OtpAccount account) async {
    final current = await future;
    if (current.any((a) => a.secret == account.secret)) return false;
    final updated = [...current, account];
    await ref.read(accountsRepositoryProvider).save(updated);
    state = AsyncData(updated);
    return true;
  }

  Future<void> remove(String id) async {
    final updated = [...await future]..removeWhere((a) => a.id == id);
    await ref.read(accountsRepositoryProvider).save(updated);
    state = AsyncData(updated);
  }

  static String newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

/// No automatic retry: unreadable account data won't fix itself, and the UI
/// must show the error (without touching the data) rather than spin.
final accountsProvider = AsyncNotifierProvider<AccountsController, List<OtpAccount>>(
  AccountsController.new,
  retry: (_, _) => null,
);
