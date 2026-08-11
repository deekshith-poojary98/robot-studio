import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Editor default. Must be a real OS face on macOS; other platforms fall back
/// through [editorFontFamilyFallback] when it is missing.
const kDefaultEditorFontFamily = 'Menlo';

const _kChannelName = 'robot_studio/fonts';

Future<List<String>>? _installedFuture;

/// Test hook: skip the platform channel and use this catalog instead.
@visibleForTesting
List<String>? debugInstalledEditorFonts;

/// Stack used when the chosen face is missing or lacks a glyph.
List<String> editorFontFamilyFallback(String current) {
  const stock = ['Menlo', 'Consolas', 'Courier New', 'monospace'];
  final family = current.trim();
  return [
    for (final name in stock)
      if (name != family) name,
  ];
}

@visibleForTesting
void debugResetEditorFontFamilyCache() {
  _installedFuture = null;
}

/// Monospace families reported by the OS. Empty when the platform channel
/// is unavailable (widget tests without an override).
Future<List<String>> installedEditorFontFamilies() {
  final override = debugInstalledEditorFonts;
  if (override != null) {
    return Future<List<String>>.value(List<String>.from(override));
  }
  return _installedFuture ??= _loadInstalledEditorFonts();
}

Future<List<String>> _loadInstalledEditorFonts() async {
  try {
    final raw = await const MethodChannel(
      _kChannelName,
    ).invokeListMethod<String>('listMonospaceFamilies');
    return _uniqueSorted(raw ?? const []);
  } on MissingPluginException {
    return const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

/// Dropdown items: OS catalog, [kDefaultEditorFontFamily] first when present,
/// plus a previously saved value so a missing face is not clobbered.
List<String> editorFontFamilyChoices(
  String current, {
  required List<String> installed,
}) {
  final trimmed = current.trim().isEmpty
      ? kDefaultEditorFontFamily
      : current.trim();
  final names = <String>{
    for (final family in installed)
      if (family.trim().isNotEmpty) family.trim(),
  };
  final ordered = <String>[];
  if (names.contains(kDefaultEditorFontFamily)) {
    ordered.add(kDefaultEditorFontFamily);
  }
  final others =
      names.where((name) => name != kDefaultEditorFontFamily).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  ordered.addAll(others);
  if (!ordered.contains(trimmed)) {
    return List<String>.unmodifiable([trimmed, ...ordered]);
  }
  return List<String>.unmodifiable(ordered);
}

List<String> _uniqueSorted(List<String> raw) {
  final names = <String>{
    for (final family in raw)
      if (family.trim().isNotEmpty) family.trim(),
  };
  final ordered = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return List<String>.unmodifiable(ordered);
}
