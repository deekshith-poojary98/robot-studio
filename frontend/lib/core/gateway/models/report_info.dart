import 'execution_info.dart';

export 'execution_info.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalRuns,
    this.passRate,
    this.averageDurationMs,
    this.lastRun,
    this.recentRuns = const [],
    this.recentFailures = const [],
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final recent = (json['recent_runs'] as List<dynamic>? ?? [])
        .map((item) => ExecutionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    final failures = (json['recent_failures'] as List<dynamic>? ?? [])
        .map((item) => ExecutionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    final last = json['last_run'];
    return DashboardSummary(
      totalRuns: (json['total_runs'] as num?)?.toInt() ?? 0,
      passRate: (json['pass_rate'] as num?)?.toDouble(),
      averageDurationMs: (json['average_duration_ms'] as num?)?.toDouble(),
      lastRun: last is Map<String, dynamic> ? ExecutionInfo.fromJson(last) : null,
      recentRuns: recent,
      recentFailures: failures,
    );
  }

  final int totalRuns;
  final double? passRate;
  final double? averageDurationMs;
  final ExecutionInfo? lastRun;
  final List<ExecutionInfo> recentRuns;
  final List<ExecutionInfo> recentFailures;

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
