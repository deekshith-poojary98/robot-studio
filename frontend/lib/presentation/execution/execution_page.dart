import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';
import 'execution_console.dart';
import 'failed_tests_panel.dart';

/// Tests center view: monitor live output for the current run.
///
/// Global launch controls live on the top toolbar (Run / Run Project / Stop),
/// menus, shortcuts, and the Test Explorer tree — not here.
/// Run history lives on Reports (and the welcome screen).
class ExecutionPage extends StatelessWidget {
  const ExecutionPage({
    super.key,
    required this.consoleLines,
    required this.status,
    required this.currentRun,
    this.failedTests = const [],
    this.isLoadingFailures = false,
    this.onJumpToFailedTest,
    this.onRerunFailedTest,
  });

  final List<String> consoleLines;
  final ExecutionStatus status;
  final ExecutionInfo? currentRun;
  final List<RunTestFailureInfo> failedTests;
  final bool isLoadingFailures;
  final void Function(RunTestFailureInfo failure)? onJumpToFailedTest;
  final void Function(RunTestFailureInfo failure)? onRerunFailedTest;

  String get _subtitle {
    if (status.isActive) {
      return 'Live output updates as the run progresses. Use the toolbar to stop.';
    }
    if (currentRun != null && currentRun!.suite.isNotEmpty) {
      return 'Last suite: ${currentRun!.suite}';
    }
    return 'Watch live output. Start from the toolbar or Test Explorer.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = status.isActive;
    final showFailures =
        !running && (isLoadingFailures || failedTests.isNotEmpty);

    return Container(
      color: context.palette.background,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Execution',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(_subtitle, style: theme.textTheme.bodySmall),
                if (currentRun != null &&
                    currentRun!.suite.isNotEmpty &&
                    running) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    currentRun!.suite,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
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
                    color: context.palette.rail,
                    child: ExecutionConsole(lines: consoleLines),
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
