import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart' show AppPalette, AppPaletteContext;

/// Dark design tokens as compile-time constants.
///
/// Prefer `context.palette` in widgets — these constants cannot follow a theme
/// switch. They remain for `const` contexts and for code with no
/// [BuildContext]; anything user-visible should migrate to [AppPalette].
abstract final class AppColors {
  static const background = Color(0xFF141416);
  static const surface = Color(0xFF1B1B1F);
  static const surfaceElevated = Color(0xFF232329);
  static const surfaceHover = Color(0xFF2A2A31);
  static const rail = Color(0xFF101012);
  static const border = Color(0xFF2E2E36);
  static const borderSubtle = Color(0xFF25252C);

  // Muted teal — understated, low-saturation accent.
  static const accent = Color(0xFF4A8F90);
  static const accentMuted = Color(0xFF3A7273);
  static const accentSoft = Color(0x184A8F90);

  static const textPrimary = Color(0xFFE8E8ED);
  static const textSecondary = Color(0xFF9A9AA6);
  static const textMuted = Color(0xFF6E6E7A);

  static const success = Color(0xFF5DDB8C);
  static const error = Color(0xFFF07A6A);
  static const warning = Color(0xFFE0C36A);
  static const info = Color(0xFF5BB8E8);

  // Near-surface charcoal with a faint teal cast — not a bright strip.
  static const statusBar = Color(0xFF121618);
  static const statusBarText = Color(0xFF8A9496);

  // Backward-compatible aliases used by existing widgets.
  static const primary = accent;
  static const primaryMuted = accentMuted;
}

abstract final class AppRadii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Two dialog widths only: [form] for prompts, [wide] for list/log content.
abstract final class AppDialogWidth {
  static const form = 420.0;
  static const wide = 480.0;
}

/// Fixed heights for chrome controls that sit side by side.
///
/// These must be explicit: the toolbar chips wrap different content (a 14px
/// icon vs an 11px label with a 6px dot), so intrinsic sizing makes them
/// disagree by a few pixels and the row stops reading as one strip.
abstract final class AppControlHeight {
  /// Toolbar project / environment / branch chips and the git overflow button.
  static const toolbarChip = 26.0;
}

/// Builds the full theme from [palette] so light and dark stay in lockstep.
///
/// Both brightnesses run through this one function on purpose: the previous
/// light theme was `buildAppTheme().copyWith(...)`, which inherited the dark
/// `textTheme` and rendered near-white text on light surfaces.
ThemeData buildAppTheme([AppPalette palette = AppPalette.dark]) {
  final isDark = palette.isDark;
  final colorScheme = ColorScheme(
    brightness: palette.brightness,
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.accentMuted,
    onSecondary: palette.onAccent,
    surface: palette.surface,
    onSurface: palette.textPrimary,
    error: palette.error,
    onError: isDark ? Colors.black : Colors.white,
    outline: palette.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.border,
    fontFamily: 'SF Pro Text',
    splashFactory: InkSparkle.splashFactory,
    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    extensions: [palette],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    iconTheme: IconThemeData(color: palette.textSecondary, size: 18),
    textTheme: TextTheme(
      bodyMedium: TextStyle(
        color: palette.textPrimary,
        fontSize: 13,
        height: 1.35,
      ),
      bodySmall: TextStyle(
        color: palette.textSecondary,
        fontSize: 12,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        color: palette.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: palette.textMuted,
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: palette.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceElevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: palette.accent),
      ),
      labelStyle: TextStyle(color: palette.textSecondary, fontSize: 12),
      hintStyle: TextStyle(color: palette.textMuted, fontSize: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: palette.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      textStyle: TextStyle(
        color: palette.textPrimary,
        fontSize: 12.5,
        height: 1.2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(color: palette.border),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12.5, height: 1.2),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: const TextStyle(fontSize: 12.5, height: 1.2),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surfaceElevated),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            side: BorderSide(color: palette.border),
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: palette.border),
      ),
      textStyle: TextStyle(color: palette.textPrimary, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceElevated,
      contentTextStyle: TextStyle(color: palette.textPrimary, fontSize: 12.5),
      actionTextColor: palette.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: palette.border),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: palette.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 0,
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      iconColor: palette.textSecondary,
      textColor: palette.textPrimary,
    ),
  );
}

ThemeData buildLightAppTheme() => buildAppTheme(AppPalette.light);

/// Maps the Appearance preference onto Flutter's own theme mode, which handles
/// `system` (including live OS appearance changes) for us.
ThemeMode appThemeModeFor(String preference) {
  return switch (preference.toLowerCase()) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
}

/// Resolves the Appearance preference (`dark` / `light` / `system`).
AppPalette resolveAppPalette({
  required String preference,
  required Brightness platformBrightness,
}) {
  final mode = preference.toLowerCase();
  if (mode == 'light') return AppPalette.light;
  if (mode == 'system' && platformBrightness == Brightness.light) {
    return AppPalette.light;
  }
  return AppPalette.dark;
}

ThemeData resolveAppTheme({
  required String preference,
  required Brightness platformBrightness,
}) {
  return buildAppTheme(
    resolveAppPalette(
      preference: preference,
      platformBrightness: platformBrightness,
    ),
  );
}
