import 'execution_info.dart';

/// Project Insights snapshot from `GET /api/v1/insights`.
class InsightsInfo {
  const InsightsInfo({
    this.composition = const {},
    this.compositionFiles = const [],
    this.runs = const InsightsRunTotals(),
    this.recentRuns = const [],
    this.runFiles = const [],
    this.indexState = 'idle',
    this.indexMessage = '',
  });

  factory InsightsInfo.fromJson(Map<String, dynamic> json) {
    final composition = <String, int>{};
    final rawComposition = json['composition'];
    if (rawComposition is Map) {
      for (final entry in rawComposition.entries) {
        composition[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return InsightsInfo(
      composition: composition,
      compositionFiles: (json['composition_files'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                InsightsFileComposition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      runs: InsightsRunTotals.fromJson(
        json['runs'] as Map<String, dynamic>? ?? const {},
      ),
      recentRuns: (json['recent_runs'] as List<dynamic>? ?? [])
          .map(
            (item) => InsightsRecentRun.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      runFiles: (json['run_files'] as List<dynamic>? ?? [])
          .map(
            (item) => InsightsFileRuns.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      indexState: json['index_state'] as String? ?? 'idle',
      indexMessage: json['index_message'] as String? ?? '',
    );
  }

  final Map<String, int> composition;
  final List<InsightsFileComposition> compositionFiles;
  final InsightsRunTotals runs;
  final List<InsightsRecentRun> recentRuns;
  final List<InsightsFileRuns> runFiles;
  final String indexState;
  final String indexMessage;

  bool get hasComposition => composition.values.any((n) => n > 0);
  bool get hasRuns => runs.total > 0;

  int countFor(String kind) => composition[kind] ?? 0;
}

class InsightsFileComposition {
  const InsightsFileComposition({
    required this.filePath,
    this.counts = const {},
  });

  factory InsightsFileComposition.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final raw = json['counts'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        counts[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return InsightsFileComposition(
      filePath: json['file_path'] as String? ?? '',
      counts: counts,
    );
  }

  final String filePath;
  final Map<String, int> counts;

  int countFor(String kind) => counts[kind] ?? 0;
}

class InsightsRunTotals {
  const InsightsRunTotals({
    this.total = 0,
    this.passed = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.aborted = 0,
    this.skippedTests = 0,
    this.passRate,
    this.averageDurationMs,
  });

  factory InsightsRunTotals.fromJson(Map<String, dynamic> json) {
    return InsightsRunTotals(
      total: (json['total'] as num?)?.toInt() ?? 0,
      passed: (json['passed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      aborted: (json['aborted'] as num?)?.toInt() ?? 0,
      skippedTests: (json['skipped_tests'] as num?)?.toInt() ?? 0,
      passRate: (json['pass_rate'] as num?)?.toDouble(),
      averageDurationMs: (json['average_duration_ms'] as num?)?.toDouble(),
    );
  }

  final int total;
  final int passed;
  final int failed;
  final int cancelled;
  final int aborted;
  final int skippedTests;
  final double? passRate;
  final double? averageDurationMs;

  /// User Stop, or a launch that never started. Insights shows these as one count.
  int get stopped => cancelled + aborted;

  String get passRateLabel {
    final rate = passRate;
    if (rate == null) return '—';
    return '${rate.toStringAsFixed(0)}%';
  }

  String get averageDurationLabel {
    final ms = averageDurationMs;
    if (ms == null) return '—';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    return '${minutes}m ${rem.toStringAsFixed(0)}s';
  }
}

class InsightsRecentRun {
  const InsightsRecentRun({
    required this.id,
    required this.startedAt,
    this.suite = '',
    this.status = ExecutionStatus.idle,
    this.durationMs,
    this.passed,
    this.failed,
    this.skipped,
    this.exitCode,
    this.outcome = '',
  });

  factory InsightsRecentRun.fromJson(Map<String, dynamic> json) {
    return InsightsRecentRun(
      id: json['id'] as String? ?? '',
      suite: json['suite'] as String? ?? '',
      status: ExecutionStatus.fromApi(json['status'] as String? ?? 'idle'),
      startedAt: DateTime.parse(json['started_at'] as String),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      passed: (json['passed'] as num?)?.toInt(),
      failed: (json['failed'] as num?)?.toInt(),
      skipped: (json['skipped'] as num?)?.toInt(),
      exitCode: (json['exit_code'] as num?)?.toInt(),
      outcome: json['outcome'] as String? ?? '',
    );
  }

  final String id;
  final String suite;
  final ExecutionStatus status;
  final DateTime startedAt;
  final int? durationMs;
  final int? passed;
  final int? failed;
  final int? skipped;
  final int? exitCode;
  final String outcome;
}

class InsightsFileRuns {
  const InsightsFileRuns({
    required this.filePath,
    this.runs = 0,
    this.passed = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.aborted = 0,
    this.lastOutcome,
    this.lastStartedAt,
    this.lastRunId,
    this.lastFailedRunId,
  });

  factory InsightsFileRuns.fromJson(Map<String, dynamic> json) {
    final last = json['last_started_at'];
    return InsightsFileRuns(
      filePath: json['file_path'] as String? ?? '',
      runs: (json['runs'] as num?)?.toInt() ?? 0,
      passed: (json['passed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      aborted: (json['aborted'] as num?)?.toInt() ?? 0,
      lastOutcome: json['last_outcome'] as String?,
      lastStartedAt: last is String ? DateTime.tryParse(last) : null,
      lastRunId: json['last_run_id'] as String?,
      lastFailedRunId: json['last_failed_run_id'] as String?,
    );
  }

  final String filePath;
  final int runs;
  final int passed;
  final int failed;
  final int cancelled;
  final int aborted;
  final String? lastOutcome;
  final DateTime? lastStartedAt;
  final String? lastRunId;
  final String? lastFailedRunId;

  int get stopped => cancelled + aborted;
}
