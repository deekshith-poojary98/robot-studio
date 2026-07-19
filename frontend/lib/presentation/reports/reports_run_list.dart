import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';

class ReportsRunList extends StatelessWidget {
  const ReportsRunList({
    super.key,
    required this.runs,
    required this.isLoading,
    this.selectedId,
    this.onSelect,
  });

  final List<ExecutionInfo> runs;
  final bool isLoading;
  final String? selectedId;
  final ValueChanged<ExecutionInfo>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (runs.isEmpty) {
      return Center(
        child: Text(
          'No reports yet. Run a suite to generate artifacts.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final run = runs[index];
        final selected = run.id == selectedId;
        return Material(
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: onSelect == null ? null : () => onSelect!(run),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          run.projectName.isEmpty ? run.suite : run.projectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      StatusBadge(
                        label: run.resultBadge,
                        filled: run.resultBadge == 'PASS',
                        dotColor: run.resultBadge == 'PASS'
                            ? AppColors.success
                            : run.resultBadge == 'FAIL'
                                ? AppColors.error
                                : AppColors.warning,
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
                    [
                      _formatTime(run.startedAt),
                      run.durationLabel,
                      if (run.environmentName.isNotEmpty) run.environmentName,
                      if (run.robotVersion != null) 'Robot ${run.robotVersion}',
                    ].join('  ·  '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
