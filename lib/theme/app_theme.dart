import 'package:flutter/material.dart';

/// Vaultline design tokens: deep graphite surfaces, brushed steel, and a mint
/// "secure" accent. Every colour in the UI comes from here.
abstract final class VColors {
  static const night = Color(0xFF0A0E13);
  static const surface = Color(0xFF111822);
  static const raised = Color(0xFF18212D);
  static const line = Color(0xFF243042);

  static const text = Color(0xFFEAF0F6);
  static const muted = Color(0xFF8A97A8);
  static const faint = Color(0x80556171);

  static const accent = Color(0xFF4BE3A6);
  static const accentDeep = Color(0xFF1FAE7A);
  static const warn = Color(0xFFFFB547);
  static const danger = Color(0xFFFF5C6C);

  /// Brushed-steel ramp for the vault door.
  static const steel = [Color(0xFFDCE3EA), Color(0xFF9AA6B3), Color(0xFFF1F5F8), Color(0xFF6E7987), Color(0xFFC3CCD5)];
}

abstract final class VSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const page = 24.0;
}

abstract final class VMotion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 650);
}

abstract final class VTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: VColors.accent,
      onPrimary: VColors.night,
      secondary: VColors.accentDeep,
      surface: VColors.surface,
      onSurface: VColors.text,
      onSurfaceVariant: VColors.muted,
      surfaceContainer: VColors.raised,
      outline: VColors.line,
      outlineVariant: VColors.line,
      error: VColors.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: VColors.night,
    );
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: t.bodyMedium?.copyWith(color: VColors.muted, height: 1.45),
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w700),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: VColors.raised,
        contentTextStyle: const TextStyle(color: VColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? VColors.night : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? VColors.accent : null),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: VColors.accent,
          foregroundColor: VColors.night,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: VColors.muted)),
    );
  }
}
