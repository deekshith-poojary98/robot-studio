import 'package:flutter/material.dart';

import 'app_accent.dart';

/// Robot Studio's colour tokens, resolved per theme.
///
/// Widgets must read these through `Theme.of(context)` (see the `palette`
/// extension below) rather than compile-time constants — that is what makes a
/// theme switch repaint. Reading a `static const` colour silently pins a widget
/// to one brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHover,
    required this.rail,
    required this.border,
    required this.borderSubtle,
    required this.accent,
    required this.accentMuted,
    required this.accentSoft,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.statusBar,
    required this.statusBarText,
  });

  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHover;
  final Color rail;
  final Color border;
  final Color borderSubtle;

  final Color accent;
  final Color accentMuted;
  final Color accentSoft;

  /// Foreground for filled accent surfaces (primary buttons).
  final Color onAccent;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color success;
  final Color error;
  final Color warning;
  final Color info;

  final Color statusBar;
  final Color statusBarText;

  bool get isDark => brightness == Brightness.dark;

  /// Backward-compatible aliases used by existing widgets.
  Color get primary => accent;
  Color get primaryMuted => accentMuted;

  /// Dark is the reference design: muted teal accent on near-black charcoal.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF141416),
    surface: Color(0xFF1B1B1F),
    surfaceElevated: Color(0xFF232329),
    surfaceHover: Color(0xFF2A2A31),
    rail: Color(0xFF101012),
    border: Color(0xFF2E2E36),
    borderSubtle: Color(0xFF25252C),
    accent: Color(0xFF4A8F90),
    accentMuted: Color(0xFF3A7273),
    accentSoft: Color(0x184A8F90),
    onAccent: Color(0xFFE8F2F2),
    textPrimary: Color(0xFFE8E8ED),
    textSecondary: Color(0xFF9A9AA6),
    textMuted: Color(0xFF6E6E7A),
    success: Color(0xFF5DDB8C),
    error: Color(0xFFF07A6A),
    warning: Color(0xFFE0C36A),
    info: Color(0xFF5BB8E8),
    statusBar: Color(0xFF121618),
    statusBarText: Color(0xFF8A9496),
  );

  /// Light keeps the same hues but re-picks lightness so text clears 4.5:1 on
  /// its own surface — the dark semantic colours are far too pale on white.
  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F3F5),
    surfaceElevated: Color(0xFFE9E9EC),
    surfaceHover: Color(0xFFDEDEE4),
    rail: Color(0xFFECECEF),
    border: Color(0xFFC9C9D1),
    borderSubtle: Color(0xFFDFDFE5),
    accent: Color(0xFF2F6F70),
    accentMuted: Color(0xFF255859),
    accentSoft: Color(0x1F2F6F70),
    onAccent: Color(0xFFF2F8F8),
    textPrimary: Color(0xFF1A1A1F),
    textSecondary: Color(0xFF54545E),
    textMuted: Color(0xFF70707A),
    success: Color(0xFF1B7A44),
    error: Color(0xFFB32718),
    warning: Color(0xFF8A6000),
    info: Color(0xFF0F5F8E),
    statusBar: Color(0xFFE6EBEC),
    statusBarText: Color(0xFF3D4A4C),
  );

  /// Base surface tokens for [brightness], with accent colours from [accent].
  factory AppPalette.forAccent(
    AppAccentPreference accent, {
    required Brightness brightness,
  }) {
    final base = brightness == Brightness.dark ? dark : light;
    final tokens = accent.tokensFor(brightness);
    return base.copyWith(
      accent: tokens.accent,
      accentMuted: tokens.accentMuted,
      accentSoft: tokens.accentSoft,
      onAccent: tokens.onAccent,
    );
  }

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHover,
    Color? rail,
    Color? border,
    Color? borderSubtle,
    Color? accent,
    Color? accentMuted,
    Color? accentSoft,
    Color? onAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    Color? statusBar,
    Color? statusBarText,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      rail: rail ?? this.rail,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      statusBar: statusBar ?? this.statusBar,
      statusBarText: statusBarText ?? this.statusBarText,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceHover: mix(surfaceHover, other.surfaceHover),
      rail: mix(rail, other.rail),
      border: mix(border, other.border),
      borderSubtle: mix(borderSubtle, other.borderSubtle),
      accent: mix(accent, other.accent),
      accentMuted: mix(accentMuted, other.accentMuted),
      accentSoft: mix(accentSoft, other.accentSoft),
      onAccent: mix(onAccent, other.onAccent),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      success: mix(success, other.success),
      error: mix(error, other.error),
      warning: mix(warning, other.warning),
      info: mix(info, other.info),
      statusBar: mix(statusBar, other.statusBar),
      statusBarText: mix(statusBarText, other.statusBarText),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// Theme-aware colour tokens for the current brightness.
  AppPalette get palette => AppPalette.of(this);
}
