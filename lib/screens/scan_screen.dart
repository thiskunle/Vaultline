import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/vault_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import 'add_methods.dart';

/// Live camera scanner for 2FA setup QR codes. A valid code opens the Add
/// account screen pre-filled; anything else gets a clear message.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  String? _lastRejected;
  bool _handled = false;
  bool _torch = false;
  bool _cameraSlow = false;
  Timer? _cameraCheck;

  @override
  void initState() {
    super.initState();
    // Some devices (e.g. the iOS Simulator) have no camera but report no
    // error either, leaving a black screen. Offer the alternatives instead.
    _cameraCheck = Timer(const Duration(seconds: 4), () {
      final state = _controller.value;
      if (mounted && !state.isRunning && state.error == null) setState(() => _cameraSlow = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _cameraCheck?.cancel();
    _sweep.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onCode(String raw) {
    // The camera reports the same code many times a second.
    if (_handled || raw == _lastRejected) return;
    final error = openScannedCode(context, ref, raw, replace: true);
    if (error == null) {
      _handled = true;
      return;
    }
    _lastRejected = raw;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  Widget _cameraError(BuildContext context, MobileScannerException e) {
    final t = Theme.of(context).textTheme;
    final message = switch (e.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is off for Vaultline. Turn it on in Settings, or add the account another way.',
      MobileScannerErrorCode.unsupported => 'This device has no camera Vaultline can use.',
      _ => 'The camera couldn’t start.',
    };
    return ColoredBox(
      color: VColors.night,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48, color: VColors.muted),
              const SizedBox(height: VSpace.md),
              Text(message, key: const Key('camera-error'), style: t.bodyMedium, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final camera = ref.watch(qrCameraProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          camera(onCode: _onCode, controller: _controller, error: _cameraError),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) => CustomPaint(painter: _ViewfinderPainter(sweep: _sweep.value)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VSpace.sm),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          'Scan QR code',
                          textAlign: TextAlign.center,
                          style: t.titleMedium?.copyWith(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        tooltip: _torch ? 'Turn off light' : 'Turn on light',
                        onPressed: () async {
                          try {
                            await _controller.toggleTorch();
                            setState(() => _torch = !_torch);
                          } catch (_) {}
                        },
                        icon: Icon(
                          _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: VSpace.xl),
                  child: Text(
                    _cameraSlow
                        ? 'The camera isn’t starting on this device. Use “From photo” or “Enter key” instead.'
                        : 'Point at the QR code shown in the service’s two-factor settings.',
                    key: const Key('scan-hint'),
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: VSpace.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('scan-from-photo'),
                          style: _outlined,
                          onPressed: () => addFromImage(context, ref, replace: true),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('From photo'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('scan-enter-key'),
                          style: _outlined,
                          onPressed: () => context.pushReplacement(Routes.addAccount),
                          icon: const Icon(Icons.keyboard_alt_outlined),
                          label: const Text('Enter key'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static final _outlined = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white38),
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

/// Dims everything outside a rounded square window, draws mint corner
/// brackets and a sweeping scan line inside it.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.sweep});
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.68;
    final window = Rect.fromCenter(center: size.center(const Offset(0, -30)), width: side, height: side);
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(28));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rrect)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final corner = Paint()
      ..color = VColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    const r = 28.0;
    for (final (dx, dy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
      final x = dx < 0 ? window.left : window.right;
      final y = dy < 0 ? window.top : window.bottom;
      final path = Path()
        ..moveTo(x, y - dy * (r + len))
        ..lineTo(x, y - dy * r)
        ..arcToPoint(Offset(x - dx * r, y), radius: const Radius.circular(r), clockwise: dx * dy > 0)
        ..lineTo(x - dx * (r + len), y);
      canvas.drawPath(path, corner);
    }

    final y = window.top + 18 + (window.height - 36) * sweep;
    canvas.drawLine(
      Offset(window.left + 20, y),
      Offset(window.right - 20, y),
      Paint()
        ..strokeWidth = 2
        ..shader = LinearGradient(
          colors: [VColors.accent.withValues(alpha: 0), VColors.accent, VColors.accent.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(window.left, y - 1, window.width, 2)),
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.sweep != sweep;
}
