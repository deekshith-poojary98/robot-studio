import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads the live Machine+User Path from Windows and builds a shell env map.
///
/// GUI apps (and shells they spawn) keep the PATH snapshot from process start.
/// After installing Node/Git/etc., Explorer terminals see the update, but a
/// long-lived Robot Studio process does not — unless we re-read the registry.
@visibleForTesting
typedef WindowsPathReader = String? Function();

/// Optional test override for [readWindowsRegistryPath].
@visibleForTesting
WindowsPathReader? debugWindowsPathReader;

/// Machine Path, then User Path, de-duplicated (Windows search order).
String? readWindowsRegistryPath() {
  final override = debugWindowsPathReader;
  if (override != null) return override();

  if (!Platform.isWindows) return null;

  try {
    final machine = _queryEnvironmentPath('Machine');
    final user = _queryEnvironmentPath('User');
    final merged = mergeWindowsPathSegments([
      ...splitWindowsPath(machine),
      ...splitWindowsPath(user),
    ]);
    return merged.isEmpty ? null : merged;
  } catch (_) {
    return null;
  }
}

/// Environment for [Pty.start]: full process env with a refreshed Windows PATH.
Map<String, String> shellEnvironmentForPty() {
  final env = Map<String, String>.from(Platform.environment);
  if (!Platform.isWindows) return env;

  final fresh = readWindowsRegistryPath();
  if (fresh == null || fresh.isEmpty) return env;

  final pathKey = env.keys.firstWhere(
    (key) => key.toUpperCase() == 'PATH',
    orElse: () => 'Path',
  );
  env[pathKey] = fresh;
  // flutter_pty looks up the literal key "PATH" when seeding defaults; set both.
  env['PATH'] = fresh;
  return env;
}

@visibleForTesting
List<String> splitWindowsPath(String? path) {
  if (path == null || path.isEmpty) return const [];
  return [
    for (final part in path.split(';'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

@visibleForTesting
String mergeWindowsPathSegments(List<String> segments) {
  final seen = <String>{};
  final out = <String>[];
  for (final segment in segments) {
    final key = segment.toLowerCase();
    if (seen.add(key)) out.add(segment);
  }
  return out.join(';');
}

String? _queryEnvironmentPath(String target) {
  // .NET expands REG_EXPAND_SZ (e.g. %SystemRoot%) the same way a new console does.
  final result = Process.runSync('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "[Environment]::GetEnvironmentVariable('Path','$target')",
  ], runInShell: false);
  if (result.exitCode != 0) return null;
  final text = (result.stdout as String?)?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
