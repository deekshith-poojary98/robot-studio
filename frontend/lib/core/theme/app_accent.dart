import 'package:flutter/material.dart';

/// Curated accent colours for Appearance. Teal is the product default.
enum AppAccentPreference {
  teal,
  blue,
  green,
  amber,
  rose,
  slate;

  static AppAccentPreference fromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'blue' => AppAccentPreference.blue,
      'green' => AppAccentPreference.green,
      'amber' => AppAccentPreference.amber,
      'rose' => AppAccentPreference.rose,
      'slate' => AppAccentPreference.slate,
      _ => AppAccentPreference.teal,
    };
  }

  String get apiValue => name;

  String get label => switch (this) {
        AppAccentPreference.teal => 'Teal (Default)',
        AppAccentPreference.blue => 'Blue',
        AppAccentPreference.green => 'Green',
        AppAccentPreference.amber => 'Amber',
        AppAccentPreference.rose => 'Rose',
        AppAccentPreference.slate => 'Slate',
      };

  /// Swatch shown in Settings (dark-theme accent).
  Color get swatch => tokensFor(Brightness.dark).accent;
}

@immutable
class AccentTokens {
  const AccentTokens({
    required this.accent,
    required this.accentMuted,
    required this.accentSoft,
    required this.onAccent,
  });

  final Color accent;
  final Color accentMuted;
  final Color accentSoft;
  final Color onAccent;
}

extension AppAccentTokens on AppAccentPreference {
  AccentTokens tokensFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      AppAccentPreference.teal => AccentTokens(
          accent: Color(dark ? 0xFF4A8F90 : 0xFF2F6F70),
          accentMuted: Color(dark ? 0xFF3A7273 : 0xFF255859),
          accentSoft: Color(dark ? 0x184A8F90 : 0x1F2F6F70),
          onAccent: Color(dark ? 0xFFE8F2F2 : 0xFFF2F8F8),
        ),
      AppAccentPreference.blue => AccentTokens(
          accent: Color(dark ? 0xFF4A7FB5 : 0xFF2B5F8F),
          accentMuted: Color(dark ? 0xFF3A658F : 0xFF234C72),
          accentSoft: Color(dark ? 0x184A7FB5 : 0x1F2B5F8F),
          onAccent: Color(dark ? 0xFFE8F1F8 : 0xFFF2F7FB),
        ),
      AppAccentPreference.green => AccentTokens(
          accent: Color(dark ? 0xFF4A9A6A : 0xFF2D6B45),
          accentMuted: Color(dark ? 0xFF3A7A54 : 0xFF245637),
          accentSoft: Color(dark ? 0x184A9A6A : 0x1F2D6B45),
          onAccent: Color(dark ? 0xFFE8F5EE : 0xFFF1F8F4),
        ),
      AppAccentPreference.amber => AccentTokens(
          accent: Color(dark ? 0xFFC49A3C : 0xFF9A6B12),
          accentMuted: Color(dark ? 0xFF9A7A30 : 0xFF7A550E),
          accentSoft: Color(dark ? 0x18C49A3C : 0x1F9A6B12),
          onAccent: Color(dark ? 0xFF1A1508 : 0xFFFFF8E8),
        ),
      AppAccentPreference.rose => AccentTokens(
          accent: Color(dark ? 0xFFC06A7A : 0xFFA13D52),
          accentMuted: Color(dark ? 0xFF9A5460 : 0xFF823142),
          accentSoft: Color(dark ? 0x18C06A7A : 0x1FA13D52),
          onAccent: Color(dark ? 0xFFF8ECEF : 0xFFFFF5F7),
        ),
      AppAccentPreference.slate => AccentTokens(
          accent: Color(dark ? 0xFF7A8494 : 0xFF4A5564),
          accentMuted: Color(dark ? 0xFF5E6876 : 0xFF3A4450),
          accentSoft: Color(dark ? 0x187A8494 : 0x1F4A5564),
          onAccent: Color(dark ? 0xFFF0F2F5 : 0xFFF7F8FA),
        ),
    };
  }
}
