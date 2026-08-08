import 'package:flutter/material.dart';

/// Curated accent colours for Appearance — popular IDE accents, UI-tuned.
///
/// Hex inspiration (syntax / theme culture) is noted in comments; filled
/// buttons and light-theme chrome use slightly quieter derivatives so contrast
/// stays readable. [teal] stays the product default and matches [AppPalette].
enum AppAccentPreference {
  /// Studio default — muted cyan/teal family (stock palette).
  teal,

  /// VS Code focus blue `#007ACC`.
  blue,

  /// Dracula purple `#BD93F9`.
  purple,

  /// Mint / Dracula green `#50FA7B`.
  mint,

  /// Warm orange `#FFB86C` (Night Owl / Material).
  orange,

  /// Soft gold / yellow `#F1FA8C` (Gruvbox / Monokai).
  gold,

  /// Salmon / coral `#FF79C6`.
  coral,

  /// Crimson / pastel red `#FF5555`.
  crimson,

  /// Burnt amber `#D65D0E` (Gruvbox).
  amber,

  /// Slate / muted silver `#6272A4`.
  slate;

  static AppAccentPreference fromApi(String value) {
    return switch (value.toLowerCase().trim()) {
      'blue' => AppAccentPreference.blue,
      // Legacy ids from the first six-colour set.
      'green' => AppAccentPreference.mint,
      'mint' => AppAccentPreference.mint,
      'purple' => AppAccentPreference.purple,
      'orange' => AppAccentPreference.orange,
      'gold' => AppAccentPreference.gold,
      'rose' => AppAccentPreference.coral,
      'coral' => AppAccentPreference.coral,
      'crimson' => AppAccentPreference.crimson,
      'amber' => AppAccentPreference.amber,
      'slate' => AppAccentPreference.slate,
      // Bright cyan from the same family as teal — treat as teal default.
      'cyan' => AppAccentPreference.teal,
      _ => AppAccentPreference.teal,
    };
  }

  String get apiValue => name;

  String get label => switch (this) {
    AppAccentPreference.blue => 'Electric Blue',
    AppAccentPreference.teal => 'Teal (Default)',
    AppAccentPreference.purple => 'Purple',
    AppAccentPreference.mint => 'Mint',
    AppAccentPreference.orange => 'Warm Orange',
    AppAccentPreference.gold => 'Soft Gold',
    AppAccentPreference.coral => 'Coral',
    AppAccentPreference.crimson => 'Crimson',
    AppAccentPreference.amber => 'Burnt Amber',
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
      // Stock AppPalette teal — must stay identical for forAccent(teal).
      AppAccentPreference.teal => AccentTokens(
        accent: Color(dark ? 0xFF4A8F90 : 0xFF2F6F70),
        accentMuted: Color(dark ? 0xFF3A7273 : 0xFF255859),
        accentSoft: Color(dark ? 0x184A8F90 : 0x1F2F6F70),
        onAccent: Color(dark ? 0xFFE8F2F2 : 0xFFF2F8F8),
      ),
      // #007ACC — already UI-friendly.
      AppAccentPreference.blue => AccentTokens(
        accent: Color(dark ? 0xFF007ACC : 0xFF0062A3),
        accentMuted: Color(dark ? 0xFF005A99 : 0xFF004A7A),
        accentSoft: Color(dark ? 0x18007ACC : 0x1F0062A3),
        onAccent: Color(dark ? 0xFFF2F8FC : 0xFFF5FAFD),
      ),
      // #BD93F9 — bright on dark; deepen for light chrome.
      AppAccentPreference.purple => AccentTokens(
        accent: Color(dark ? 0xFFBD93F9 : 0xFF7A52C7),
        accentMuted: Color(dark ? 0xFF9B74D9 : 0xFF5E3D9E),
        accentSoft: Color(dark ? 0x18BD93F9 : 0x1F7A52C7),
        onAccent: Color(dark ? 0xFF1A1228 : 0xFFF8F4FF),
      ),
      // #50FA7B
      AppAccentPreference.mint => AccentTokens(
        accent: Color(dark ? 0xFF50FA7B : 0xFF1F9E48),
        accentMuted: Color(dark ? 0xFF3BC861 : 0xFF187A38),
        accentSoft: Color(dark ? 0x1850FA7B : 0x1F1F9E48),
        onAccent: Color(dark ? 0xFF0A1A10 : 0xFFF2FBF5),
      ),
      // #FFB86C
      AppAccentPreference.orange => AccentTokens(
        accent: Color(dark ? 0xFFFFB86C : 0xFFC47420),
        accentMuted: Color(dark ? 0xFFD99A4F : 0xFF9A5A18),
        accentSoft: Color(dark ? 0x18FFB86C : 0x1FC47420),
        onAccent: Color(dark ? 0xFF1A1208 : 0xFFFFF8F0),
      ),
      // #F1FA8C
      AppAccentPreference.gold => AccentTokens(
        accent: Color(dark ? 0xFFE8F070 : 0xFF7A7A12),
        accentMuted: Color(dark ? 0xFFC4CC55 : 0xFF5C5C0E),
        accentSoft: Color(dark ? 0x18E8F070 : 0x1F7A7A12),
        onAccent: Color(dark ? 0xFF1A1A08 : 0xFFFFFCE8),
      ),
      // #FF79C6
      AppAccentPreference.coral => AccentTokens(
        accent: Color(dark ? 0xFFFF79C6 : 0xFFC43D8A),
        accentMuted: Color(dark ? 0xFFD95AA8 : 0xFF9A2E6C),
        accentSoft: Color(dark ? 0x18FF79C6 : 0x1FC43D8A),
        onAccent: Color(dark ? 0xFF1A0C14 : 0xFFFFF5FA),
      ),
      // #FF5555
      AppAccentPreference.crimson => AccentTokens(
        accent: Color(dark ? 0xFFFF5555 : 0xFFD32F2F),
        accentMuted: Color(dark ? 0xFFD94444 : 0xFFB71C1C),
        accentSoft: Color(dark ? 0x18FF5555 : 0x1FD32F2F),
        onAccent: Color(dark ? 0xFF1A0808 : 0xFFFFF5F5),
      ),
      // #D65D0E
      AppAccentPreference.amber => AccentTokens(
        accent: Color(dark ? 0xFFE07020 : 0xFFD65D0E),
        accentMuted: Color(dark ? 0xFFB85A18 : 0xFFA8480A),
        accentSoft: Color(dark ? 0x18E07020 : 0x1FD65D0E),
        onAccent: Color(dark ? 0xFF1A0E06 : 0xFFFFF8F0),
      ),
      // #6272A4
      AppAccentPreference.slate => AccentTokens(
        accent: Color(dark ? 0xFF6272A4 : 0xFF4A5780),
        accentMuted: Color(dark ? 0xFF4E5A84 : 0xFF3A4464),
        accentSoft: Color(dark ? 0x186272A4 : 0x1F4A5780),
        onAccent: Color(dark ? 0xFFF0F2F8 : 0xFFF5F6FA),
      ),
    };
  }
}
