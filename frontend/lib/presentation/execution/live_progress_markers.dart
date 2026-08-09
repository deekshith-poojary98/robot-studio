/// Parse Studio progress markers embedded in Robot console output.
///
/// Listener lines look like: `###RS###|now|<suite>|<test>|<keyword>`
/// Robot may glue that onto a padded suite/test row, so the marker is not
/// always at column 0.
library;

final RegExp progressMarkerPattern = RegExp(r'###RS###\|now\|([^\r\n]*)');

class ProgressMarkerResult {
  const ProgressMarkerResult({
    required this.suite,
    required this.test,
    required this.keyword,
    this.consoleLine,
  });

  final String suite;
  final String test;
  final String keyword;

  /// Remaining console text after stripping the marker, or null to drop the line.
  final String? consoleLine;
}

/// Returns null when [line] has no progress marker.
ProgressMarkerResult? parseProgressMarker(String line) {
  final match = progressMarkerPattern.firstMatch(line);
  if (match == null) return null;
  final parts = match.group(1)!.split('|');
  final suite = parts.isNotEmpty ? parts[0] : '';
  final test = parts.length > 1 ? parts[1] : '';
  final keyword = parts.length > 2 ? parts.sublist(2).join('|') : '';
  final cleaned = line.replaceAll(progressMarkerPattern, '').trimRight();
  return ProgressMarkerResult(
    suite: suite,
    test: test,
    keyword: keyword,
    consoleLine: cleaned.trim().isEmpty ? null : cleaned,
  );
}
