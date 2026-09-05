enum ExecutionStatus {
  idle,
  starting,
  running,
  stopping,
  finished,
  failed,
  cancelled,
  aborted;

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
    ExecutionStatus.aborted => 'Aborted',
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
    this.configurationId,
    this.configurationName = '',
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
      configurationId: json['configuration_id'] as String?,
      configurationName: json['configuration_name'] as String? ?? '',
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
  final String? configurationId;
  final String configurationName;

  String get configurationLabel =>
      configurationName.trim().isEmpty ? 'Default' : configurationName;

  bool get isPassBadge => resultBadge == 'PASS';

  /// Whether Execution should fetch / show the Failed Tests list.
  ///
  /// A non-zero Robot exit is not enough: `--include smoke` with no matches
  /// exits 252 and marks the run failed, but there are no failed tests.
  bool get shouldListFailures {
    if (failed != null) return failed! > 0;
    final code = exitCode ?? 0;
    // Robot: 1–250 = failed-test count (250 = 250+). 252 = no tests / invalid.
    return code >= 1 && code <= 250;
  }

  /// User-facing outcome. FAIL is only for failed **tests**, not Robot CLI
  /// errors (empty selection / invalid data = 252, crash = 255).
  String get resultBadge {
    if (status == ExecutionStatus.cancelled || exitCode == 253) {
      return 'CANCELLED';
    }
    if (status == ExecutionStatus.aborted) return 'ABORTED';
    if ((failed ?? 0) > 0) return 'FAIL';
    final code = exitCode ?? 0;
    if (code == 252) return 'NO TESTS';
    // Empty suites before the exit-code FAIL heuristic (see backend result_badge).
    // Exit 0 is a Robot pass — do not treat missing stats (stream finish
    // before output.xml is indexed) as NO TESTS.
    final emptySelection =
        (status == ExecutionStatus.finished ||
            status == ExecutionStatus.failed) &&
        (totalTests ?? 0) == 0 &&
        (passed ?? 0) == 0 &&
        (failed ?? 0) == 0 &&
        code != 0 &&
        code != 255;
    if (emptySelection) return 'NO TESTS';
    if (failed == null && code >= 1 && code <= 250) return 'FAIL';
    if (code == 0) {
      if (status == ExecutionStatus.finished) return 'PASS';
      return status.label.toUpperCase();
    }
    return 'ERROR';
  }

  /// Toolbar / toast wording for [resultBadge] (title case, not FAIL/NO TESTS).
  String get outcomeLabel => switch (resultBadge) {
    'PASS' => 'Passed',
    'FAIL' => 'Failed',
    'NO TESTS' => 'No tests',
    'ERROR' => 'Error',
    'CANCELLED' => 'Cancelled',
    'ABORTED' => 'Aborted',
    final other => other,
  };

  String get durationLabel {
    final ms = durationMs;
    if (ms == null) return '—';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    return '${minutes}m ${rem.toStringAsFixed(0)}s';
  }

  /// Label derived from `Reports/Run-*` output folder (or a short id fallback).
  String get runNumberLabel {
    final dir = outputDir;
    if (dir != null && dir.isNotEmpty) {
      final name = dir.replaceAll('\\', '/').split('/').last;
      if (name.startsWith('Run-')) {
        // Run-YYYYMMDD-HHMMSS-ffffff → Run YYYYMMDD-HHMMSS
        final parts = name.split('-');
        if (parts.length >= 3) {
          return 'Run ${parts[1]}-${parts[2]}';
        }
        return name.replaceFirst('Run-', 'Run ');
      }
      if (name.isNotEmpty) return name;
    }
    final short = id.length > 8 ? id.substring(0, 8) : id;
    return 'Run $short';
  }

  /// Compact sidebar / list title (result is shown via icon colour).
  String get sidebarLabel => runNumberLabel;
}

class ExecutionStatusInfo {
  const ExecutionStatusInfo({required this.status, this.run});

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
