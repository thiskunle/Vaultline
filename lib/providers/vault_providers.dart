import 'package:flutter_riverpod/flutter_riverpod.dart';

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
