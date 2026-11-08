import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../security/biometrics.dart';
import '../security/lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_pad.dart';
import '../widgets/vault_door.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  bool _busy = false;
  bool _opening = false;
  bool _error = false;
  int _errorTick = 0;
  String? _message;
  DateTime? _lockedUntil;
  Timer? _ticker;
  bool _autoPrompted = false;

  LockService get _lock => ref.read(lockServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadLockout();
  }

  Future<void> _loadLockout() async {
    final until = await _lock.lockedUntil();
    if (mounted && until != null) _startLockout(until);
  }

  void _startLockout(DateTime until) {
    _ticker?.cancel();
    setState(() {
      _lockedUntil = until;
      _pin = '';
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_lockedUntil!)) {
        _ticker?.cancel();
        setState(() {
          _lockedUntil = null;
          _message = null;
          _error = false;
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _digit(String d) {
    if (_busy || _opening || _lockedUntil != null || _pin.length >= LockService.pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == LockService.pinLength) _submit();
  }

  void _delete() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final result = await _lock.unlockWithPin(_pin);
    if (!mounted) return;
    switch (result) {
      case Unlocked():
        HapticFeedback.mediumImpact();
        setState(() {
          _busy = false;
          _opening = true;
          _message = null;
        });
      case WrongPin(:final attemptsBeforeLockout):
        HapticFeedback.heavyImpact();
        setState(() {
          _busy = false;
          _pin = '';
          _error = true;
          _errorTick++;
          _message = attemptsBeforeLockout <= 2
              ? 'Wrong PIN. $attemptsBeforeLockout ${attemptsBeforeLockout == 1 ? 'try' : 'tries'} left before a timed lock.'
              : 'Wrong PIN. Try again.';
        });
      case LockedOut(:final until):
        HapticFeedback.heavyImpact();
        setState(() {
          _busy = false;
          _error = true;
          _errorTick++;
        });
        _startLockout(until);
    }
  }

  Future<void> _biometric() async {
    if (_busy || _opening || _lockedUntil != null) return;
    setState(() => _busy = true);
    final ok = await ref.read(biometricsProvider).authenticate('Unlock your vault');
    if (!mounted) return;
    if (ok) {
      await _lock.recordBiometricUnlock();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _opening = true;
      });
    } else {
      setState(() => _busy = false);
    }
  }

  String _countdown() {
    final left = _lockedUntil!.difference(DateTime.now());
    final s = left.inSeconds.clamp(0, 9999) + 1;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = ref.watch(biometricKindProvider).value ?? BiometricKind.none;
    final bioOn = ref.watch(biometricEnabledProvider).value ?? false;
    final useBio = bioOn && kind != BiometricKind.none;

    // Offer biometrics once, as soon as we know they're on.
    if (useBio && !_autoPrompted && _lockedUntil == null) {
      _autoPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }

    final lockedOut = _lockedUntil != null;
    final status = lockedOut ? 'Too many attempts. Try again in ${_countdown()}.' : _message;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            VaultDoor(
              state: _opening
                  ? VaultDoorState.unlocking
                  : (_error || lockedOut)
                  ? VaultDoorState.error
                  : VaultDoorState.locked,
              errorTick: _errorTick,
              size: 190,
              onOpened: () => ref.read(vaultControllerProvider.notifier).markUnlocked(),
            ),
            const SizedBox(height: VSpace.lg),
            Text('VAULTLINE', style: t.labelSmall?.copyWith(color: VColors.accent)),
            const SizedBox(height: VSpace.sm),
            Text(_opening ? 'Opening…' : 'Enter your PIN', style: t.headlineSmall),
            const SizedBox(height: VSpace.lg),
            PinDots(length: LockService.pinLength, filled: _pin.length, error: _error, errorTick: _errorTick),
            SizedBox(
              height: 48,
              child: Center(
                child: AnimatedSwitcher(
                  duration: VMotion.fast,
                  child: status == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(status.split('.').first),
                          padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
                          child: Text(
                            status,
                            key: const Key('lock-message'),
                            textAlign: TextAlign.center,
                            style: t.bodyMedium?.copyWith(color: lockedOut ? VColors.warn : VColors.danger),
                          ),
                        ),
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: PinPad(
                enabled: !_busy && !_opening && !lockedOut,
                onDigit: _digit,
                onDelete: _delete,
                biometric: useBio ? kind : BiometricKind.none,
                onBiometric: useBio ? _biometric : null,
              ),
            ),
            const SizedBox(height: VSpace.lg),
          ],
        ),
      ),
    );
  }
}
