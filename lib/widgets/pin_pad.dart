import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security/biometrics.dart';
import '../theme/app_theme.dart';

/// Row of PIN dots: filled as digits are entered, red with a shake on error.
class PinDots extends StatefulWidget {
  const PinDots({super.key, required this.length, required this.filled, this.error = false, this.errorTick = 0});

  final int length;
  final int filled;
  final bool error;
  final int errorTick;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void didUpdateWidget(PinDots old) {
    super.didUpdateWidget(old);
    if (widget.error && (widget.errorTick != old.errorTick || !old.error)) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.filled} of ${widget.length} digits entered',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, _) => Transform.translate(
          offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.length, (i) {
              final on = i < widget.filled;
              final color = widget.error ? VColors.danger : VColors.accent;
              return AnimatedContainer(
                duration: VMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? color : Colors.transparent,
                  border: Border.all(color: on ? color : VColors.muted.withValues(alpha: 0.6), width: 1.6),
                  boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)] : null,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Number pad: 1–9, then [biometric], 0, [delete]. Large circular keys with a
/// haptic tick, labelled for screen readers.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    this.onBiometric,
    this.biometric = BiometricKind.none,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometric;
  final BiometricKind biometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _Key(
      label: d,
      enabled: enabled,
      onTap: () => onDigit(d),
      child: Text(
        d,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: VColors.text),
      ),
    );

    final bio = biometric == BiometricKind.none || onBiometric == null
        ? const SizedBox.square(dimension: 76)
        : _Key(
            key: const Key('biometric-key'),
            label: biometric == BiometricKind.face ? 'Unlock with Face ID' : 'Unlock with fingerprint',
            enabled: enabled,
            plain: true,
            onTap: onBiometric!,
            child: Icon(
              biometric == BiometricKind.face ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded,
              size: 32,
              color: VColors.accent,
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final d in row) digit(d)]),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            bio,
            digit('0'),
            _Key(
              key: const Key('delete-key'),
              label: 'Delete',
              enabled: enabled,
              plain: true,
              onTap: onDelete,
              child: const Icon(Icons.backspace_outlined, size: 24, color: VColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.plain = false,
  });

  final String label;
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  /// No ring (biometric and delete keys).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: SizedBox.square(
          dimension: 76,
          child: Material(
            color: plain ? Colors.transparent : VColors.raised.withValues(alpha: 0.85),
            shape: CircleBorder(side: plain ? BorderSide.none : const BorderSide(color: VColors.line)),
            child: InkWell(
              key: plain ? null : Key('key-$label'),
              customBorder: const CircleBorder(),
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap();
                    }
                  : null,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
