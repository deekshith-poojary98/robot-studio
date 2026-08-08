import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';

void main() {
  group('palette-driven themes', () {
    test('each brightness carries its own palette extension', () {
      expect(
        buildAppTheme(AppPalette.dark).extension<AppPalette>(),
        AppPalette.dark,
      );
      expect(
        buildAppTheme(AppPalette.light).extension<AppPalette>(),
        AppPalette.light,
      );
    });

    test('light theme does not inherit dark foregrounds', () {
      final light = buildAppTheme(AppPalette.light);

      // The old buildLightAppTheme copyWith'd the dark theme, leaving
      // near-white body text and list tiles on light surfaces.
      expect(light.brightness, Brightness.light);
      expect(light.textTheme.bodyMedium!.color, AppPalette.light.textPrimary);
      expect(light.listTileTheme.textColor, AppPalette.light.textPrimary);
      expect(light.iconTheme.color, AppPalette.light.textSecondary);
      expect(light.scaffoldBackgroundColor, AppPalette.light.background);

      final darkPalette = AppPalette.dark;
      for (final color in [
        light.textTheme.bodyMedium!.color,
        light.textTheme.titleLarge!.color,
        light.listTileTheme.textColor,
      ]) {
        expect(color, isNot(darkPalette.textPrimary));
      }
    });

    test('body text clears 4.5:1 against its own surface', () {
      for (final palette in [AppPalette.dark, AppPalette.light]) {
        expect(
          _contrast(palette.textPrimary, palette.background),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightness} textPrimary on background',
        );
        expect(
          _contrast(palette.textSecondary, palette.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightness} textSecondary on surface',
        );
      }
    });

    test('semantic colours stay readable on their surface', () {
      for (final palette in [AppPalette.dark, AppPalette.light]) {
        final semantics = {
          'success': palette.success,
          'error': palette.error,
          'warning': palette.warning,
          'info': palette.info,
          'accent': palette.accent,
        };
        semantics.forEach((name, color) {
          expect(
            _contrast(color, palette.surface),
            greaterThanOrEqualTo(3.0),
            reason: '${palette.brightness} $name on surface',
          );
        });
      }
    });

    test('onAccent is readable on an accent fill', () {
      for (final palette in [AppPalette.dark, AppPalette.light]) {
        expect(
          _contrast(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(3.0),
          reason: '${palette.brightness} onAccent on accent',
        );
      }
    });

    test('forAccent keeps teal identical to the stock palettes', () {
      expect(
        AppPalette.forAccent(
          AppAccentPreference.teal,
          brightness: Brightness.dark,
        ).accent,
        AppPalette.dark.accent,
      );
      expect(
        AppPalette.forAccent(
          AppAccentPreference.teal,
          brightness: Brightness.light,
        ).accent,
        AppPalette.light.accent,
      );
    });

    test('forAccent swaps only accent tokens', () {
      final blue = AppPalette.forAccent(
        AppAccentPreference.blue,
        brightness: Brightness.dark,
      );
      expect(blue.accent, isNot(AppPalette.dark.accent));
      expect(blue.background, AppPalette.dark.background);
      expect(blue.textPrimary, AppPalette.dark.textPrimary);
      expect(
        _contrast(blue.onAccent, blue.accent),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('appThemeModeFor', () {
    test('maps the stored preference', () {
      expect(appThemeModeFor('light'), ThemeMode.light);
      expect(appThemeModeFor('dark'), ThemeMode.dark);
      expect(appThemeModeFor('system'), ThemeMode.system);
      expect(appThemeModeFor('LIGHT'), ThemeMode.light);
      expect(appThemeModeFor('nonsense'), ThemeMode.dark);
    });
  });

  testWidgets('context.palette follows MaterialApp themeMode', (tester) async {
    late AppPalette seen;

    Future<void> pumpWith(ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          darkTheme: buildAppTheme(AppPalette.dark),
          themeMode: mode,
          home: Builder(
            builder: (context) {
              seen = context.palette;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(ThemeMode.dark);
    expect(seen.brightness, Brightness.dark);
    expect(seen.background, AppPalette.dark.background);

    await pumpWith(ThemeMode.light);
    expect(seen.brightness, Brightness.light);
    expect(seen.background, AppPalette.light.background);
  });

  testWidgets('a const widget still repaints on theme change', (tester) async {
    // Regression guard for the reason this uses ThemeExtension rather than a
    // mutable global: const widgets short-circuit rebuilds, but an
    // InheritedWidget dependency still invalidates them.
    Future<void> pumpWith(ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          darkTheme: buildAppTheme(AppPalette.dark),
          themeMode: mode,
          home: const _ConstPaletteBox(),
        ),
      );
      await tester.pumpAndSettle();
    }

    final box = find.descendant(
      of: find.byType(_ConstPaletteBox),
      matching: find.byType(ColoredBox),
    );

    await pumpWith(ThemeMode.dark);
    expect(tester.widget<ColoredBox>(box).color, AppPalette.dark.surface);

    await pumpWith(ThemeMode.light);
    expect(tester.widget<ColoredBox>(box).color, AppPalette.light.surface);
  });
}

class _ConstPaletteBox extends StatelessWidget {
  const _ConstPaletteBox();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.palette.surface);
  }
}

/// WCAG relative luminance contrast ratio.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double component) {
    return component <= 0.03928
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
