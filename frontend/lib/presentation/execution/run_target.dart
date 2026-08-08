/// Resolves which suite Run should execute.
///
/// Run File only targets an open editor tab that is a `.robot` suite — never
/// an Explorer selection or a previously sticky suite while no file is open.
bool isRunnableSuitePath(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  final lower = path.toLowerCase().replaceAll('\\', '/');
  return lower.endsWith('.robot');
}

/// Returns the active editor path when it is a runnable `.robot` suite.
String? resolveRunTargetPath({required String? activeEditorPath}) {
  if (isRunnableSuitePath(activeEditorPath)) return activeEditorPath;
  return null;
}
