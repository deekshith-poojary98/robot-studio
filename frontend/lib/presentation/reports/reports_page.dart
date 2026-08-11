import 'package:flutter/material.dart';

import '../../core/gateway/models/report_info.dart';
import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import 'run_details_panel.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.isLoading,
    required this.dashboard,
    required this.isLoadingDashboard,
    this.selected,
    this.failedTests = const [],
    this.isLoadingFailures = false,
    this.failuresReady = true,
    this.onJumpToFailedTest,
    this.onRerunFailedTest,
    this.onRefresh,
    this.onOpenXml,
    this.onOpenLog,
    this.onOpenReport,
    this.onReveal,
    this.onDelete,
  });

  final bool isLoading;
  final DashboardSummary? dashboard;
  final bool isLoadingDashboard;
  final ExecutionInfo? selected;
  final List<RunTestFailureInfo> failedTests;
  final bool isLoadingFailures;
  final bool failuresReady;
  final void Function(RunTestFailureInfo failure)? onJumpToFailedTest;
  final void Function(RunTestFailureInfo failure)? onRerunFailedTest;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenXml;
  final VoidCallback? onOpenLog;
  final VoidCallback? onOpenReport;
  final VoidCallback? onReveal;
  final VoidCallback? onDelete;

  bool get _showDashboard {
    if (isLoadingDashboard && dashboard == null) return true;
    final data = dashboard;
    return data != null && data.totalRuns > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reports',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Browse Robot Framework execution artifacts and run statistics.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          if (_showDashboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: _DashboardStrip(
                dashboard: dashboard,
                isLoading: isLoadingDashboard,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: isLoading && selected == null
                ? const Center(child: CircularProgressIndicator())
                : selected == null
                ? const EmptyState(
                    icon: Icons.assessment_outlined,
                    title: 'No run selected',
                    message:
                        'Pick a run in the Reports list to open its '
                        'log, report, and statistics.',
                  )
                : RunDetailsPanel(
                    run: selected!,
                    failedTests: failedTests,
                    isLoadingFailures: isLoadingFailures,
                    failuresReady: failuresReady,
                    onJumpToFailedTest: onJumpToFailedTest,
                    onRerunFailedTest: onRerunFailedTest,
                    onOpenXml: onOpenXml,
                    onOpenLog: onOpenLog,
                    onOpenReport: onOpenReport,
                    onReveal: onReveal,
                    onDelete: onDelete,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStrip extends StatelessWidget {
  const _DashboardStrip({required this.dashboard, required this.isLoading});

  final DashboardSummary? dashboard;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading && dashboard == null) {
      return const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final data = dashboard;
    if (data == null || data.totalRuns == 0) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetricChip(label: 'Total Runs', value: '${data.totalRuns}'),
        _MetricChip(label: 'Pass Rate', value: data.passRateLabel),
        _MetricChip(label: 'Avg Duration', value: data.averageDurationLabel),
        _MetricChip(
          label: 'Last Run',
          value: _lastRunLabel(data.lastRun),
          emphasize: data.lastRun?.resultBadge == 'FAIL',
        ),
        _MetricChip(
          label: 'Recent Failures',
          value: '${data.recentFailures.length}',
          emphasize: data.recentFailures.isNotEmpty,
        ),
      ],
    );
  }
}

String _lastRunLabel(ExecutionInfo? run) {
  if (run == null) return '—';
  return switch (run.resultBadge) {
    'PASS' => 'Finished',
    'NO TESTS' => 'No tests',
    'ERROR' => 'Error',
    _ => run.resultBadge,
  };
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: emphasize
              ? context.palette.error.withValues(alpha: 0.45)
              : context.palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: emphasize
                  ? context.palette.error
                  : context.palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
