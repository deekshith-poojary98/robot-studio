import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'execution_console.dart';
import 'execution_history_list.dart';
import 'failed_tests_panel.dart';

/// Tests center view: monitor live output and recent runs.
///
/// Global launch controls live on the top toolbar (Run / Run Project / Stop),
/// menus, shortcuts, and the Test Explorer tree — not here.
class ExecutionPage extends StatelessWidget {
  const ExecutionPage({
    super.key,
    required this.consoleLines,
    required this.history,
    required this.isLoadingHistory,
    required this.status,
    required this.currentRun,
    required this.elapsedLabel,
    this.onRefreshHistory,
    this.failedTests = const [],
    this.isLoadingFailures = false,
    this.onJumpToFailedTest,
    this.onRerunFailedTest,
  });

  final List<String> consoleLines;
  final List<ExecutionInfo> history;
  final bool isLoadingHistory;
  final ExecutionStatus status;
  final ExecutionInfo? currentRun;
  final String elapsedLabel;
  final VoidCallback? onRefreshHistory;
  final List<RunTestFailureInfo> failedTests;
  final bool isLoadingFailures;
  final void Function(RunTestFailureInfo failure)? onJumpToFailedTest;
  final void Function(RunTestFailureInfo failure)? onRerunFailedTest;

  Color get _statusDot {
    if (status.isActive) return AppColors.accent;
    return switch (status) {
      ExecutionStatus.failed || ExecutionStatus.aborted => AppColors.error,
      ExecutionStatus.finished => AppColors.success,
      ExecutionStatus.cancelled => AppColors.warning,
      _ => AppColors.textMuted,
    };
  }

  String get _statusLabel {
    if (status.isActive) return '${status.label} · $elapsedLabel';
    if (status == ExecutionStatus.idle) return 'Idle';
    return status.label;
  }

  String get _subtitle {
    if (status.isActive) {
      return 'Live output updates as the run progresses. Use the toolbar to stop.';
    }
    if (currentRun != null && currentRun!.suite.isNotEmpty) {
      return 'Last suite: ${currentRun!.suite}';
    }
    return 'Watch live output and recent runs. Start from the toolbar or Test Explorer.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = status.isActive;
    final showFailures =
        !running && (isLoadingFailures || failedTests.isNotEmpty);

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Execution',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (currentRun != null &&
                          currentRun!.suite.isNotEmpty &&
                          running) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          currentRun!.suite,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                StatusBadge(
                  label: _statusLabel.toUpperCase(),
                  dotColor: _statusDot,
                  filled: running,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (showFailures)
            FailedTestsPanel(
              failures: failedTests,
              isLoading: isLoadingFailures,
              onJumpToSource: onJumpToFailedTest,
              onRerunTest: onRerunFailedTest,
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          'Live Output',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ColoredBox(
                          color: AppColors.rail,
                          child: ExecutionConsole(lines: consoleLines),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: ExecutionHistoryList(
                    runs: history,
                    isLoading: isLoadingHistory,
                    onRefresh: onRefreshHistory,
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
