/// Client-side large-run confirmation helpers.
///
/// Threshold must come from [ExecutionSettings.largeRunThreshold] (same value
/// the backend uses for HTTP 409). Do not hardcode a second threshold.
class LargeRunGuard {
  LargeRunGuard._();

  /// Matches [ExecutionSettings.largeRunThreshold] default when unset.
  static const int defaultThreshold = 100;

  /// Tag filters that can expand unpredictably (wildcard / boolean AND/OR/NOT).
  static bool isWildcardTag(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final upper = tag.toUpperCase();
    return tag.contains('*') ||
        tag.contains('?') ||
        upper.contains('OR') ||
        upper.contains('AND') ||
        upper.contains('NOT');
  }

  /// Whether the UI should ask before starting this run.
  ///
  /// Confirmation is required when [count] is strictly greater than
  /// [threshold], or when [tag] is a wildcard/boolean expression.
  static bool needsConfirmation({
    required int count,
    required int threshold,
    String? tag,
  }) {
    return count > threshold || isWildcardTag(tag);
  }
}
