import 'dart:convert';
import 'dart:math';

import 'pin_hasher.dart';
import 'secure_store.dart';

sealed class UnlockResult {
  const UnlockResult();
}

class Unlocked extends UnlockResult {
  const Unlocked();
}

class WrongPin extends UnlockResult {
  const WrongPin({required this.attemptsBeforeLockout});

  /// Wrong attempts left before a timed lockout starts (0 = locked out now).
  final int attemptsBeforeLockout;
}

class LockedOut extends UnlockResult {
  const LockedOut(this.until);
  final DateTime until;
}

/// PIN setup, verification and brute-force protection.
///
/// After [freeAttempts] consecutive wrong PINs the vault locks for 30 s; each
/// further miss doubles the wait, up to 15 min. The counter and deadline are
/// persisted, so restarting the app doesn't reset them.
class LockService {
  LockService({required this.store, this.hasher = const PinHasher(), DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final SecureStore store;
  final PinHasher hasher;
  final DateTime Function() _now;

  static const pinLength = 6;
  static const freeAttempts = 5;
  static const baseLockout = Duration(seconds: 30);
  static const maxLockout = Duration(minutes: 15);

  static const _pinKey = 'vaultline.pin.v1';
  static const _failKey = 'vaultline.failures.v1';
  static const _bioKey = 'vaultline.biometric.v1';

  Future<bool> hasPin() async => await store.read(_pinKey) != null;

  static bool isValidPin(String pin) => pin.length == pinLength && RegExp(r'^\d+$').hasMatch(pin);

  /// Rejects trivially guessable PINs (all the same digit, straight runs).
  static bool isWeakPin(String pin) {
    if (pin.split('').toSet().length == 1) return true;
    const runs = '0123456789012345';
    const back = '9876543210987654';
    return runs.contains(pin) || back.contains(pin);
  }

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be $pinLength digits');
    final record = await hasher.create(pin);
    await store.write(_pinKey, record.encode());
    await _writeFailures(0, null);
  }

  /// Current lockout deadline, if one is in force.
  Future<DateTime?> lockedUntil() async {
    final (_, until) = await _readFailures();
    return until != null && until.isAfter(_now()) ? until : null;
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final until = await lockedUntil();
    if (until != null) return LockedOut(until);

    final raw = await store.read(_pinKey);
    if (raw == null) throw StateError('No PIN set');
    final ok = isValidPin(pin) && await hasher.verify(pin, PinRecord.decode(raw));
    if (ok) {
      await _writeFailures(0, null);
      return const Unlocked();
    }

    final (failures, _) = await _readFailures();
    final count = failures + 1;
    if (count >= freeAttempts) {
      final extra = count - freeAttempts; // 0 for the 5th miss, 1 for the 6th…
      final wait = Duration(seconds: min(baseLockout.inSeconds * pow(2, extra).toInt(), maxLockout.inSeconds));
      final deadline = _now().add(wait);
      await _writeFailures(count, deadline);
      return LockedOut(deadline);
    }
    await _writeFailures(count, null);
    return WrongPin(attemptsBeforeLockout: freeAttempts - count);
  }

  /// Called after a successful biometric unlock.
  Future<void> recordBiometricUnlock() => _writeFailures(0, null);

  Future<bool> biometricEnabled() async => await store.read(_bioKey) == 'on';

  Future<void> setBiometricEnabled(bool on) => on ? store.write(_bioKey, 'on') : store.delete(_bioKey);

  Future<(int, DateTime?)> _readFailures() async {
    final raw = await store.read(_failKey);
    if (raw == null) return (0, null);
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final until = m['until'] as String?;
      return (m['count'] as int, until == null ? null : DateTime.parse(until));
    } catch (_) {
      // Tampered or corrupt: keep counting from a safe non-zero state.
      return (freeAttempts - 1, null);
    }
  }

  Future<void> _writeFailures(int count, DateTime? until) =>
      store.write(_failKey, jsonEncode({'count': count, 'until': until?.toIso8601String()}));
}
