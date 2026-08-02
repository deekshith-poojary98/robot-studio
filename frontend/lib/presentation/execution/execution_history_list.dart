import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';

class ExecutionHistoryList extends StatelessWidget {
  const ExecutionHistoryList({
    super.key,
    required this.runs,
    this.isLoading = false,
    this.onRefresh,
  });

  final List<ExecutionInfo> runs;
  final bool isLoading;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(
                'Recent Runs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : runs.isEmpty
                  ? Center(
                      child: Text(
                        'No executions yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: runs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final run = runs[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      run.projectName.isEmpty
                                          ? run.suite
                                          : run.projectName,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  StatusBadge(
                                    label: run.status.label.toUpperCase(),
                                    filled: run.status == ExecutionStatus.finished,
                                    dotColor: _statusColor(run.status),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                run.suite,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatTime(run.startedAt)}  ·  ${run.durationLabel}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Color _statusColor(ExecutionStatus status) {
    return switch (status) {
      ExecutionStatus.finished => AppColors.success,
      ExecutionStatus.failed => AppColors.error,
      ExecutionStatus.cancelled => AppColors.warning,
      ExecutionStatus.aborted => AppColors.warning,
      ExecutionStatus.running ||
      ExecutionStatus.starting ||
      ExecutionStatus.stopping =>
        AppColors.accent,
      ExecutionStatus.idle => AppColors.textMuted,
    };
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
