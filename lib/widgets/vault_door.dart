import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

enum VaultDoorState { locked, error, unlocking }

/// The animated vault door.
///
/// * locked: closed, bolts out, status light breathing.
/// * error: the door shudders and the light flashes red.
/// * unlocking: the wheel spins, bolts retract, then the door swings open on
///   its left hinge toward the viewer; [onOpened] fires when it's done.
///
/// Honours the system "reduce motion" setting.
class VaultDoor extends StatefulWidget {
  const VaultDoor({super.key, required this.state, this.size = 220, this.onOpened, this.errorTick = 0});

  final VaultDoorState state;
  final double size;
  final VoidCallback? onOpened;

  /// Bump to replay the error shudder for repeated mistakes.
  final int errorTick;

  @override
  State<VaultDoor> createState() => _VaultDoorState();
}

class _VaultDoorState extends State<VaultDoor> with TickerProviderStateMixin {
  late final _wheel = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _bolts = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _sequenceStarted = false;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_reduced && !_breathe.isAnimating) _breathe.repeat(reverse: true);
    if (widget.state == VaultDoorState.unlocking) _startUnlock();
  }

  @override
  void didUpdateWidget(VaultDoor old) {
    super.didUpdateWidget(old);
    if (widget.state == VaultDoorState.unlocking && old.state != VaultDoorState.unlocking) _startUnlock();
    if (widget.state == VaultDoorState.error &&
        (old.state != VaultDoorState.error || widget.errorTick != old.errorTick)) {
      _shake.forward(from: 0);
    }
    if (widget.state == VaultDoorState.locked && old.state == VaultDoorState.unlocking) {
      _sequenceStarted = false;
      for (final c in [_wheel, _bolts, _open]) {
        c.value = 0;
      }
    }
  }

  Future<void> _startUnlock() async {
    if (_sequenceStarted) return;
    _sequenceStarted = true;
    // Let this frame finish before animating (may be called during build).
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_reduced) {
      _wheel.value = 1;
      _bolts.value = 1;
      _open.value = 1;
    } else {
      await _wheel.forward(from: 0);
      await _bolts.forward(from: 0);
      await _open.forward(from: 0);
    }
    if (mounted) widget.onOpened?.call();
  }

  @override
  void dispose() {
    for (final c in [_wheel, _bolts, _open, _shake, _breathe]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_wheel, _bolts, _open, _shake, _breathe]),
      builder: (context, _) {
        final s = widget.size;
        final open = Curves.easeInOutCubic.transform(_open.value);
        final shake = math.sin(_shake.value * math.pi * 8) * 7 * (1 - _shake.value);
        final error = widget.state == VaultDoorState.error;
        final unlocking = widget.state == VaultDoorState.unlocking;
        final light = error
            ? VColors.danger
            : unlocking
            ? VColors.accent
            : Color.lerp(VColors.accentDeep.withValues(alpha: 0.35), VColors.accent, _breathe.value * 0.6)!;

        return Semantics(
          label: unlocking ? 'Vault opening' : 'Vault locked',
          child: SizedBox.square(
            dimension: s,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Wall frame and the glowing interior revealed as it opens.
                Positioned.fill(
                  child: CustomPaint(painter: _FramePainter(glow: open)),
                ),
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(shake, 0),
                    child: Transform(
                      alignment: Alignment.centerLeft,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0016)
                        ..rotateY(-open * 1.25),
                      child: CustomPaint(
                        painter: _DoorPainter(
                          wheel: Curves.easeInOutCubic.transform(_wheel.value) * math.pi * 2.25,
                          bolts: Curves.easeInCubic.transform(_bolts.value),
                          light: light,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.glow});
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Recess in the wall.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF05070A), Color(0xFF1B2430)],
          stops: [0.82, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    if (glow > 0) {
      canvas.drawCircle(
        c,
        r * 0.86,
        Paint()
          ..shader = RadialGradient(
            colors: [
              VColors.accent.withValues(alpha: 0.55 * glow),
              VColors.accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.86)),
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.glow != glow;
}

class _DoorPainter extends CustomPainter {
  const _DoorPainter({required this.wheel, required this.bolts, required this.light});
  final double wheel;

  /// 0 = bolts out (locked), 1 = fully retracted.
  final double bolts;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final doorR = r * 0.86;

    // Locking bolts reaching into the frame.
    const boltCount = 10;
    final boltPaint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFFB8C2CD), Color(0xFF6B7684)]).createShader(Offset.zero & size);
    for (var i = 0; i < boltCount; i++) {
      final a = i / boltCount * math.pi * 2 + math.pi / boltCount;
      final reach = r * 0.11 * (1 - bolts);
      if (reach <= 0.5) continue;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(doorR - 4, -r * 0.035, reach + 4, r * 0.07), const Radius.circular(3)),
        boltPaint,
      );
      canvas.restore();
    }

    // Door: brushed steel disc with a bevel and drop shadow.
    canvas.drawCircle(c.translate(0, r * 0.04), doorR, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawCircle(
      c,
      doorR,
      Paint()
        ..shader = SweepGradient(
          colors: [...VColors.steel, VColors.steel.first],
          transform: const GradientRotation(-0.6),
        ).createShader(Rect.fromCircle(center: c, radius: doorR)),
    );
    final ring = Paint()..style = PaintingStyle.stroke;
    for (var k = 0; k < 14; k++) {
      ring
        ..strokeWidth = 0.6
        ..color = (k.isEven ? Colors.white : Colors.black).withValues(alpha: 0.06);
      canvas.drawCircle(c, doorR * (0.3 + k * 0.05), ring);
    }
    canvas.drawCircle(
      c,
      doorR - 2,
      ring
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      c,
      doorR * 0.72,
      ring
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.18),
    );

    // Dial ticks.
    final tick = Paint()
      ..strokeWidth = 1.4
      ..color = Colors.black.withValues(alpha: 0.35);
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2;
      final inner = doorR * (i % 5 == 0 ? 0.6 : 0.64);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * doorR * 0.68,
        tick,
      );
    }

    // Handle wheel: hub plus three spokes with grips, rotating as one.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(wheel);
    final spoke = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.075
      ..shader = const LinearGradient(colors: [Color(0xFF2A333F), Color(0xFF4A5563)])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: doorR));
    for (var i = 0; i < 3; i++) {
      final a = i / 3 * math.pi * 2 - math.pi / 2;
      final end = Offset(math.cos(a), math.sin(a)) * doorR * 0.5;
      canvas.drawLine(Offset.zero, end, spoke);
      canvas.drawCircle(end, r * 0.07, Paint()..color = const Color(0xFF1C232D));
      canvas.drawCircle(
        end,
        r * 0.07,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.18),
      );
    }
    canvas.drawCircle(
      Offset.zero,
      r * 0.16,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF5B6675), Color(0xFF1C232D)])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.16)),
    );
    canvas.restore();

    // Status light.
    final lightPos = c.translate(0, -doorR * 0.82);
    canvas.drawCircle(lightPos, r * 0.05, Paint()..color = light.withValues(alpha: 0.35));
    canvas.drawCircle(lightPos, r * 0.028, Paint()..color = light);
  }

  @override
  bool shouldRepaint(_DoorPainter old) => old.wheel != wheel || old.bolts != bolts || old.light != light;
}
