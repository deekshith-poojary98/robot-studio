/// Curated monospace faces offered in Settings → Editor → Font Family.
///
/// Ranked by common IDE usage (VS Code / JetBrains / Windows Terminal surveys).
/// The OS still has to have the face installed — unknown names fall back silently
/// in Flutter, which is why this is a fixed list rather than a free-text field.
const kEditorFontFamilies = <String>[
  'Menlo', // Robot Studio default; stock on macOS
  'JetBrains Mono',
  'Fira Code',
  'Cascadia Code',
  'Consolas',
  'Source Code Pro',
  'Monaco',
  'Roboto Mono',
  'IBM Plex Mono',
  'Courier New',
];

/// Items for the font-family dropdown, preserving a legacy/custom value if the
/// user already saved something outside the curated list.
List<String> editorFontFamilyChoices(String current) {
  final trimmed = current.trim().isEmpty ? 'Menlo' : current.trim();
  if (kEditorFontFamilies.contains(trimmed)) {
    return List<String>.unmodifiable(kEditorFontFamilies);
  }
  return List<String>.unmodifiable([trimmed, ...kEditorFontFamilies]);
}
