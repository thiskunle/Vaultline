import 'package:local_auth/local_auth.dart';

enum BiometricKind { none, face, fingerprint, other }

/// Device biometrics (Face ID / Touch ID / fingerprint / face unlock).
abstract interface class Biometrics {
  /// What the device offers right now (enrolled and allowed), or none.
  Future<BiometricKind> available();

  /// Shows the system prompt. False on cancel, failure or any error.
  Future<bool> authenticate(String reason);
}

class PlatformBiometrics implements Biometrics {
  PlatformBiometrics();

  final _auth = LocalAuthentication();

  @override
  Future<BiometricKind> available() async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return BiometricKind.none;
      final kinds = await _auth.getAvailableBiometrics();
      if (kinds.contains(BiometricType.face)) return BiometricKind.face;
      if (kinds.contains(BiometricType.fingerprint)) return BiometricKind.fingerprint;
      if (kinds.isNotEmpty) return BiometricKind.other;
      return BiometricKind.none;
    } catch (_) {
      return BiometricKind.none;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Biometric only: the device passcode must not bypass the vault PIN.
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }
}
