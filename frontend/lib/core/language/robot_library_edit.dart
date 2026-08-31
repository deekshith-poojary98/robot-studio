/// Inserts a Robot ``Library`` setting into a suite / resource buffer.
///
/// Returns null when [library] is already imported. Mirrors the backend helper
/// so Problems **Fix** can apply the edit without another round-trip.
String? insertLibraryImport(String content, String library) {
  final name = library.trim();
  if (name.isEmpty || _libraryAlreadyImported(content, name)) {
    return null;
  }

  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  final row = 'Library    $name';
  if (content.trim().isEmpty) {
    return '*** Settings ***$newline$row$newline';
  }

  final hadTrailing = content.endsWith('\n');
  final lines = content.split(RegExp(r'\r?\n'));
  if (hadTrailing && lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  var settingsAt = -1;
  var sectionEnd = lines.length;
  final settingsHeader = RegExp(r'^\*+\s*settings?\s*\*+', caseSensitive: false);
  final sectionHeader = RegExp(r'^\*+\s+\S+');

  for (var i = 0; i < lines.length; i++) {
    final stripped = lines[i].trim();
    if (settingsAt < 0 && settingsHeader.hasMatch(stripped)) {
      settingsAt = i;
      continue;
    }
    if (settingsAt >= 0 && i > settingsAt && sectionHeader.hasMatch(stripped)) {
      sectionEnd = i;
      break;
    }
  }

  if (settingsAt < 0) {
    return '*** Settings ***$newline$row$newline$newline$content';
  }

  var lastLibrary = settingsAt;
  for (var i = settingsAt + 1; i < sectionEnd; i++) {
    if (lines[i].trim().toLowerCase().startsWith('library ')) {
      lastLibrary = i;
    }
  }
  lines.insert(lastLibrary + 1, row);
  final next = lastLibrary + 2;
  if (next < lines.length &&
      lines[next].trim().startsWith('*') &&
      (next == 0 || lines[next - 1].trim().isNotEmpty)) {
    lines.insert(next, '');
  }
  var joined = lines.join(newline);
  if (hadTrailing) joined = '$joined$newline';
  return joined;
}

bool _libraryAlreadyImported(String content, String library) {
  final target = library.trim().toLowerCase();
  for (final raw in content.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (!line.toLowerCase().startsWith('library ')) continue;
    final rest = line.substring('library'.length).trim();
    final token = rest.split(RegExp(r'[ \t]{2,}|\t+')).first.trim();
    if (token.toLowerCase() == target) return true;
  }
  return false;
}
