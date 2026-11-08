import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/otp_account.dart';
import '../otp/totp.dart';
import '../theme/app_theme.dart';

/// Groups a code for reading aloud: "482913" → "482 913", 8 digits → 4+4.
String groupCode(String code) {
  final half = code.length ~/ 2;
  return '${code.substring(0, half)} ${code.substring(half)}';
}

/// Deterministic accent colour for an issuer's badge.
Color issuerColor(String issuer) {
  const palette = [
    Color(0xFF4BE3A6),
    Color(0xFF6CB6FF),
    Color(0xFFB79CFF),
    Color(0xFFFF9E7A),
    Color(0xFFFFD166),
    Color(0xFF5FD1E0),
  ];
  final h = issuer.toLowerCase().codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
  return palette[h % palette.length];
}

/// One account: badge, issuer and account name, the live code and a ring
/// counting down to the next one. Rebuilds on [tick]; the code itself is
/// only recomputed when the time step changes.
class AccountCard extends StatefulWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.tick,
    required this.now,
    required this.onCopy,
    required this.onMore,
  });

  final OtpAccount account;
  final Listenable tick;
  final DateTime Function() now;
  final ValueChanged<String> onCopy;
  final VoidCallback onMore;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  String? _cacheKey;
  String _code = '';

  /// Recomputes only when the time step or the account's settings change.
  String _codeAt(DateTime t) {
    final a = widget.account;
    final key = '${a.secret}|${a.digits}|${a.period}|${a.algorithm.name}|${Otp.counterAt(t, period: a.period)}';
    if (key != _cacheKey) {
      _cacheKey = key;
      _code = a.codeAt(t);
    }
    return _code;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = widget.account;
    final color = issuerColor(a.issuer);

    return AnimatedBuilder(
      animation: widget.tick,
      builder: (context, _) {
        final now = widget.now();
        final code = _codeAt(now);
        final left = Otp.secondsLeft(now, period: a.period);
        final ending = left <= 5;

        return Semantics(
          button: true,
          label:
              '${a.issuer}${a.name.isEmpty ? '' : ', ${a.name}'}. Code ${code.split('').join(' ')}. '
              '$left seconds left. Double tap to copy.',
          excludeSemantics: true,
          child: Material(
            color: VColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              key: Key('account-${a.id}'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => widget.onCopy(code),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: VColors.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.14),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        a.issuer.isEmpty ? '?' : a.issuer.characters.first.toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.issuer, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (a.name.isNotEmpty)
                            Text(
                              a.name,
                              style: t.bodySmall?.copyWith(color: VColors.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 6),
                          AnimatedDefaultTextStyle(
                            duration: VMotion.fast,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                              color: ending ? VColors.warn : VColors.text,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            child: Text(groupCode(code), key: Key('code-${a.id}')),
                          ),
                        ],
                      ),
                    ),
                    CountdownRing(
                      progress: Otp.progress(now, period: a.period),
                      secondsLeft: left,
                      warning: ending,
                    ),
                    IconButton(
                      tooltip: 'More for ${a.issuer}',
                      onPressed: widget.onMore,
                      icon: const Icon(Icons.more_vert_rounded, color: VColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ring that empties as the code's time runs out, with seconds inside.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, required this.secondsLeft, this.warning = false});

  final double progress;
  final int secondsLeft;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? VColors.warn : VColors.accent;
    return SizedBox.square(
      dimension: 40,
      child: CustomPaint(
        painter: _RingPainter(remaining: 1 - progress, color: color),
        child: Center(
          child: Text(
            '$secondsLeft',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.remaining, required this.color});
  final double remaining;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = VColors.line;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * remaining,
      false,
      base
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.remaining != remaining || old.color != color;
}
