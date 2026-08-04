/// Resolves which suite Run should execute.
///
/// Trust rule: never silently run a sticky suite while a non-`.robot` editor
/// is focused (avoids "notes.txt runs tests/foo.robot").
bool isRunnableSuitePath(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  final lower = path.toLowerCase().replaceAll('\\', '/');
  return lower.endsWith('.robot');
}

/// Prefer the active editor when it is a `.robot` suite; use sticky only when
/// no editor is focused.
String? resolveRunTargetPath({
  required String? activeEditorPath,
  required String? stickySuitePath,
}) {
  final active = activeEditorPath;
  if (isRunnableSuitePath(active)) return active;
  if (active != null && active.trim().isNotEmpty) {
    return null;
  }
  if (isRunnableSuitePath(stickySuitePath)) return stickySuitePath;
  return null;
}
