enum ExecutionStatus {
  idle,
  starting,
  running,
  stopping,
  finished,
  failed,
  cancelled;

  static ExecutionStatus fromApi(String value) {
    return ExecutionStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ExecutionStatus.idle,
    );
  }

  String get label => switch (this) {
        ExecutionStatus.idle => 'Idle',
        ExecutionStatus.starting => 'Starting',
        ExecutionStatus.running => 'Running',
        ExecutionStatus.stopping => 'Stopping',
        ExecutionStatus.finished => 'Finished',
        ExecutionStatus.failed => 'Failed',
        ExecutionStatus.cancelled => 'Cancelled',
      };

  bool get isActive =>
      this == ExecutionStatus.starting ||
      this == ExecutionStatus.running ||
      this == ExecutionStatus.stopping;

  bool get isPass =>
      this == ExecutionStatus.finished && (this != ExecutionStatus.failed);

  String get passFailLabel {
    if (this == ExecutionStatus.finished) return 'PASS';
    if (this == ExecutionStatus.failed) return 'FAIL';
    return label.toUpperCase();
  }
}

class ExecutionInfo {
  const ExecutionInfo({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.environmentId,
    required this.projectName,
    required this.suite,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.durationMs,
    this.exitCode,
    this.command = '',
    this.outputDir,
    this.outputXml,
    this.logHtml,
    this.reportHtml,
    this.environmentName = '',
    this.robotVersion,
    this.totalTests,
    this.passed,
    this.failed,
    this.skipped,
  });

  factory ExecutionInfo.fromJson(Map<String, dynamic> json) {
    return ExecutionInfo(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      projectId: json['project_id'] as String,
      environmentId: json['environment_id'] as String,
      projectName: json['project_name'] as String? ?? '',
      suite: json['suite'] as String? ?? '',
      status: ExecutionStatus.fromApi(json['status'] as String),
      startedAt: DateTime.parse(json['started_at'] as String),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      exitCode: (json['exit_code'] as num?)?.toInt(),
      command: json['command'] as String? ?? '',
      outputDir: json['output_dir'] as String?,
      outputXml: json['output_xml'] as String?,
      logHtml: json['log_html'] as String?,
      reportHtml: json['report_html'] as String?,
      environmentName: json['environment_name'] as String? ?? '',
      robotVersion: json['robot_version'] as String?,
      totalTests: (json['total_tests'] as num?)?.toInt(),
      passed: (json['passed'] as num?)?.toInt(),
      failed: (json['failed'] as num?)?.toInt(),
      skipped: (json['skipped'] as num?)?.toInt(),
    );
  }

  final String id;
  final String workspaceId;
  final String projectId;
  final String environmentId;
  final String projectName;
  final String suite;
  final ExecutionStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final int? exitCode;
  final String command;
  final String? outputDir;
  final String? outputXml;
  final String? logHtml;
  final String? reportHtml;
  final String environmentName;
  final String? robotVersion;
  final int? totalTests;
  final int? passed;
  final int? failed;
  final int? skipped;

  bool get isPassBadge =>
      status == ExecutionStatus.finished &&
      (exitCode == 0 || (failed ?? 0) == 0);

  String get resultBadge {
    if (status == ExecutionStatus.cancelled) return 'CANCELLED';
    if (status == ExecutionStatus.failed || (failed ?? 0) > 0 || (exitCode ?? 0) != 0) {
      return 'FAIL';
    }
    if (status == ExecutionStatus.finished) return 'PASS';
    return status.label.toUpperCase();
  }

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '—';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    return '${minutes}m ${rem.toStringAsFixed(0)}s';
  }
}

class ExecutionStatusInfo {
  const ExecutionStatusInfo({
    required this.status,
    this.run,
  });

  factory ExecutionStatusInfo.fromJson(Map<String, dynamic> json) {
    final runJson = json['run'];
    return ExecutionStatusInfo(
      status: ExecutionStatus.fromApi(json['status'] as String),
      run: runJson is Map<String, dynamic>
          ? ExecutionInfo.fromJson(runJson)
          : null,
    );
  }

  final ExecutionStatus status;
  final ExecutionInfo? run;
}

class ExecutionStreamEvent {
  const ExecutionStreamEvent({
    required this.type,
    this.runId,
    this.line,
    this.status,
    this.message,
    this.exitCode,
  });

  factory ExecutionStreamEvent.fromJson(Map<String, dynamic> json) {
    return ExecutionStreamEvent(
      type: json['type'] as String? ?? 'unknown',
      runId: json['run_id'] as String?,
      line: json['line'] as String?,
      status: json['status'] as String?,
      message: json['message'] as String?,
      exitCode: (json['exit_code'] as num?)?.toInt(),
    );
  }

  final String type;
  final String? runId;
  final String? line;
  final String? status;
  final String? message;
  final int? exitCode;
}
