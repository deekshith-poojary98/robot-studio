import 'package:flutter/material.dart';

import '../../core/gateway/models/report_info.dart';
import '../../core/theme/app_theme.dart';
import 'reports_run_list.dart';
import 'run_details_panel.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.runs,
    required this.isLoading,
    required this.dashboard,
    required this.isLoadingDashboard,
    this.selected,
    this.onRefresh,
    this.onSelect,
    this.onOpenLog,
    this.onOpenReport,
    this.onReveal,
    this.onDelete,
  });

  final List<ExecutionInfo> runs;
  final bool isLoading;
  final DashboardSummary? dashboard;
  final bool isLoadingDashboard;
  final ExecutionInfo? selected;
  final VoidCallback? onRefresh;
  final ValueChanged<ExecutionInfo>? onSelect;
  final VoidCallback? onOpenLog;
  final VoidCallback? onOpenReport;
  final VoidCallback? onReveal;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: _DashboardStrip(
              dashboard: dashboard,
              isLoading: isLoadingDashboard,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 340,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Recent Runs',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Expanded(
                        child: ReportsRunList(
                          runs: runs,
                          isLoading: isLoading,
                          selectedId: selected?.id,
                          onSelect: onSelect,
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selected == null
                      ? Center(
                          child: Text(
                            'Select a run to view details.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : RunDetailsPanel(
                          run: selected!,
                          onOpenLog: onOpenLog,
                          onOpenReport: onOpenReport,
                          onReveal: onReveal,
                          onDelete: onDelete,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStrip extends StatelessWidget {
  const _DashboardStrip({
    required this.dashboard,
    required this.isLoading,
  });

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
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'No runs indexed yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
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
          value: data.lastRun?.resultBadge ?? '—',
        ),
        _MetricChip(
          label: 'Recent Failures',
          value: '${data.recentFailures.length}',
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
