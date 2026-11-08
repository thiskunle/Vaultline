import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../security/biometrics.dart';
import '../security/lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_pad.dart';
import '../widgets/vault_door.dart';

enum _Step { create, confirm, saving, biometric, opening }

/// First launch: create a PIN, confirm it, optionally turn on biometrics,
/// then open the vault.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Step _step = _Step.create;
  String _first = '';
  String _pin = '';
  bool _error = false;
  int _errorTick = 0;
  String? _message;

  void _digit(String d) {
    if (_pin.length >= LockService.pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == LockService.pinLength) _complete();
  }

  void _delete() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _error = true;
      _errorTick++;
      _message = message;
    });
  }

  Future<void> _complete() async {
    if (_step == _Step.create) {
      if (LockService.isWeakPin(_pin)) {
        _fail('That PIN is too easy to guess. Try another.');
        return;
      }
      setState(() {
        _first = _pin;
        _pin = '';
        _message = null;
        _step = _Step.confirm;
      });
      return;
    }
    if (_pin != _first) {
      _fail('Those PINs didn’t match. Start again.');
      setState(() {
        _first = '';
        _step = _Step.create;
      });
      return;
    }
    setState(() => _step = _Step.saving);
    await ref.read(lockServiceProvider).setPin(_pin);
    final kind = await ref.read(biometricKindProvider.future);
    if (!mounted) return;
    setState(() => _step = kind == BiometricKind.none ? _Step.opening : _Step.biometric);
  }

  Future<void> _enableBiometric() async {
    final ok = await ref.read(biometricsProvider).authenticate('Turn on biometric unlock');
    if (ok) await ref.read(biometricEnabledProvider.notifier).set(true);
    if (mounted) setState(() => _step = _Step.opening);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = ref.watch(biometricKindProvider).value ?? BiometricKind.none;
    final (title, subtitle) = switch (_step) {
      _Step.create => ('Create your vault PIN', 'Six digits. You’ll use it to open Vaultline.'),
      _Step.confirm => ('Confirm your PIN', 'Enter the same six digits again.'),
      _Step.saving => ('Securing your vault…', 'Hashing your PIN on this device.'),
      _Step.biometric => (
        kind == BiometricKind.face ? 'Unlock with Face ID?' : 'Unlock with your fingerprint?',
        'Faster than typing your PIN. Your PIN still works.',
      ),
      _Step.opening => ('Your vault is ready', 'Opening…'),
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            VaultDoor(
              state: _step == _Step.opening
                  ? VaultDoorState.unlocking
                  : _error
                  ? VaultDoorState.error
                  : VaultDoorState.locked,
              errorTick: _errorTick,
              size: 170,
              onOpened: () => ref.read(vaultControllerProvider.notifier).markUnlocked(),
            ),
            const SizedBox(height: VSpace.lg),
            Text('VAULTLINE', style: t.labelSmall?.copyWith(color: VColors.accent)),
            const SizedBox(height: VSpace.sm),
            Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Text(subtitle, style: t.bodyMedium, textAlign: TextAlign.center),
            ),
            const SizedBox(height: VSpace.lg),
            if (_step == _Step.create || _step == _Step.confirm)
              PinDots(length: LockService.pinLength, filled: _pin.length, error: _error, errorTick: _errorTick),
            SizedBox(
              height: 48,
              child: Center(
                child: _message == null
                    ? null
                    : Text(
                        _message!,
                        key: const Key('setup-message'),
                        style: t.bodyMedium?.copyWith(color: VColors.danger),
                      ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: switch (_step) {
                _Step.create || _Step.confirm => PinPad(onDigit: _digit, onDelete: _delete),
                _Step.biometric => Column(
                  children: [
                    FilledButton.icon(
                      key: const Key('enable-biometric'),
                      onPressed: _enableBiometric,
                      icon: Icon(
                        kind == BiometricKind.face ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded,
                      ),
                      label: Text(kind == BiometricKind.face ? 'Use Face ID' : 'Use fingerprint'),
                    ),
                    const SizedBox(height: VSpace.sm),
                    TextButton(
                      key: const Key('skip-biometric'),
                      onPressed: () => setState(() => _step = _Step.opening),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
                _ => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive())),
              },
            ),
            const SizedBox(height: VSpace.lg),
          ],
        ),
      ),
    );
  }
}
