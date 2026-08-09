import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';
import 'execution_console.dart';
import 'failed_tests_panel.dart';

/// Tests center view: monitor live output for the current run.
///
/// Global launch controls live on the top toolbar (Run / Project / Stop),
/// menus, shortcuts, and the Tests tree — not here.
/// Run history lives on Reports (and the welcome screen).
class ExecutionPage extends StatelessWidget {
  const ExecutionPage({
    super.key,
    required this.consoleLines,
    required this.status,
    required this.currentRun,
    this.liveSuite = '',
    this.liveTest = '',
    this.liveKeyword = '',
    this.failedTests = const [],
    this.isLoadingFailures = false,
    this.onJumpToFailedTest,
    this.onRerunFailedTest,
  });

  final List<String> consoleLines;
  final ExecutionStatus status;
  final ExecutionInfo? currentRun;

  /// RIDE-style progress from the Studio listener (stripped from console).
  final String liveSuite;
  final String liveTest;
  final String liveKeyword;

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
    return 'Watch live output. Start from the toolbar or Tests.';
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: context.palette.border,
                ),
                SizedBox(
                  width: 280,
                  child: _NowRunningPanel(
                    running: running,
                    suite: liveSuite,
                    test: liveTest,
                    keyword: liveKeyword,
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

class _NowRunningPanel extends StatelessWidget {
  const _NowRunningPanel({
    required this.running,
    required this.suite,
    required this.test,
    required this.keyword,
  });

  final bool running;
  final String suite;
  final String test;
  final String keyword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final hasAny = suite.isNotEmpty || test.isNotEmpty || keyword.isNotEmpty;

    return ColoredBox(
      color: palette.surface,
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Now Running',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (running)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: !running && !hasAny
                  ? Text(
                      'Suite, test, and keyword appear here while a run is in progress.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProgressField(
                          label: 'Suite',
                          value: suite,
                          emptyHint: running ? 'Starting…' : '—',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ProgressField(
                          label: 'Test',
                          value: test,
                          emptyHint: running ? 'Waiting…' : '—',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _ProgressField(
                          label: 'Keyword',
                          value: keyword,
                          emptyHint: running ? 'Waiting…' : '—',
                          emphasize: true,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressField extends StatelessWidget {
  const _ProgressField({
    required this.label,
    required this.value,
    required this.emptyHint,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String emptyHint;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final display = value.isEmpty ? emptyHint : value;
    final muted = value.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: palette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          display,
          style:
              (emphasize && !muted
                      ? theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        )
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: muted ? palette.textMuted : palette.textPrimary,
                  ),
        ),
      ],
    );
  }
}
