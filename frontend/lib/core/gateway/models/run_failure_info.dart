class RunTestFailureInfo {
  const RunTestFailureInfo({
    required this.runId,
    required this.name,
    required this.message,
    required this.source,
    this.line,
    this.column,
    this.entityId,
    this.durationMs = 0,
    this.status = 'FAIL',
  });

  factory RunTestFailureInfo.fromJson(Map<String, dynamic> json) {
    return RunTestFailureInfo(
      runId: json['run_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? '',
      line: json['line'] as int?,
      column: json['column'] as int?,
      entityId: json['entity_id'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'FAIL',
    );
  }

  final String runId;
  final String name;
  final String message;
  final String source;
  final int? line;
  final int? column;
  final String? entityId;
  final double durationMs;
  final String status;

  bool get canJump => source.trim().isNotEmpty;
}

class RunFailuresInfo {
  const RunFailuresInfo({
    required this.runId,
    required this.items,
  });

  factory RunFailuresInfo.fromJson(Map<String, dynamic> json) {
    return RunFailuresInfo(
      runId: json['run_id'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RunTestFailureInfo.fromJson)
          .toList(),
    );
  }

  final String runId;
  final List<RunTestFailureInfo> items;
}
