import 'package:flutter/material.dart';

/// Design tokens for Robot Studio (dark-mode first).
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

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: Color(0xFFE8F2F2),
    secondary: AppColors.accentMuted,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.error,
    onError: Colors.black,
    outline: AppColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    fontFamily: 'SF Pro Text',
    splashFactory: InkSparkle.splashFactory,
    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    iconTheme: const IconThemeData(
      color: AppColors.textSecondary,
      size: 18,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        height: 1.35,
      ),
      bodySmall: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      textStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12.5,
        height: 1.2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: const BorderSide(color: AppColors.border),
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
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceElevated),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFFE8F2F2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12.5,
      ),
      actionTextColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 0,
      minLeadingWidth: 28,
      contentPadding: EdgeInsets.symmetric(horizontal: 10),
      iconColor: AppColors.textSecondary,
      textColor: AppColors.textPrimary,
    ),
  );
}

/// Minimal light theme for Appearance → Light / System.
ThemeData buildLightAppTheme() {
  final base = buildAppTheme();
  return base.copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFECECEF),
    colorScheme: const ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: Color(0xFFE8F2F2),
      secondary: AppColors.accentMuted,
      onSecondary: Colors.white,
      surface: Color(0xFFF4F4F6),
      onSurface: Color(0xFF1A1A1F),
      error: AppColors.error,
      onError: Colors.white,
      outline: Color(0xFFD0D0D6),
    ),
  );
}

ThemeData resolveAppTheme({
  required String preference,
  required Brightness platformBrightness,
}) {
  final mode = preference.toLowerCase();
  if (mode == 'light') return buildLightAppTheme();
  if (mode == 'system' && platformBrightness == Brightness.light) {
    return buildLightAppTheme();
  }
  return buildAppTheme();
}
