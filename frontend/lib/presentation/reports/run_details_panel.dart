import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';
import '../execution/failed_tests_panel.dart';

class RunDetailsPanel extends StatelessWidget {
  const RunDetailsPanel({
    super.key,
    required this.run,
    this.failedTests = const [],
    this.isLoadingFailures = false,
    this.failuresReady = true,
    this.onJumpToFailedTest,
    this.onRerunFailedTest,
    this.onOpenXml,
    this.onOpenLog,
    this.onOpenReport,
    this.onReveal,
    this.onDelete,
  });

  final ExecutionInfo run;
  final List<RunTestFailureInfo> failedTests;
  final bool isLoadingFailures;

  /// When false, the Failed Tests block stays hidden during a quiet load.
  final bool failuresReady;
  final void Function(RunTestFailureInfo failure)? onJumpToFailedTest;
  final void Function(RunTestFailureInfo failure)? onRerunFailedTest;
  final VoidCallback? onOpenXml;
  final VoidCallback? onOpenLog;
  final VoidCallback? onOpenReport;
  final VoidCallback? onReveal;
  final VoidCallback? onDelete;

  bool get _showFailedTests {
    if (failedTests.isNotEmpty || isLoadingFailures) return true;
    if (!failuresReady) return false;
    return (run.failed ?? 0) > 0 || run.resultBadge == 'FAIL';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            run.projectName.isEmpty ? 'Run Details' : run.projectName,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(run.suite, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          _Section(
            title: 'General',
            child: Column(
              children: [
                _DetailRow(label: 'Status', value: run.status.label),
                _DetailRow(
                  label: 'Started',
                  value: _formatDateTime(run.startedAt),
                ),
                _DetailRow(
                  label: 'Finished',
                  value: run.finishedAt == null
                      ? '—'
                      : _formatDateTime(run.finishedAt!),
                ),
                _DetailRow(label: 'Duration', value: run.durationLabel),
                _DetailRow(
                  label: 'Exit code',
                  value: run.exitCode?.toString() ?? '—',
                ),
                _DetailRow(
                  label: 'Environment',
                  value: run.environmentName.isEmpty
                      ? '—'
                      : run.environmentName,
                ),
                _DetailRow(
                  label: 'Configuration',
                  value: run.configurationLabel,
                ),
                _DetailRow(
                  label: 'Robot Version',
                  value: run.robotVersion ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Statistics',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StatCard(label: 'Total', value: _n(run.totalTests)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatCard(label: 'Passed', value: _n(run.passed)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatCard(
                    label: 'Failed',
                    value: _n(run.failed),
                    color: (run.failed ?? 0) > 0 ? context.palette.error : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatCard(
                    label: 'Skipped',
                    value: _n(run.skipped),
                    color: (run.skipped ?? 0) > 0
                        ? context.palette.warning
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (_showFailedTests) ...[
            const SizedBox(height: 14),
            _Section(
              title: 'Failed Tests',
              child: FailedTestsPanel(
                failures: failedTests,
                isLoading: isLoadingFailures,
                embedded: true,
                onJumpToSource: onJumpToFailedTest,
                onRerunTest: onRerunFailedTest,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _Section(
            title: 'Artifacts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ArtifactRow(
                  label: 'output.xml',
                  path: run.outputXml,
                  onOpen: run.outputXml == null ? null : onOpenXml,
                ),
                _ArtifactRow(
                  label: 'log.html',
                  path: run.logHtml,
                  onOpen: run.logHtml == null ? null : onOpenLog,
                ),
                _ArtifactRow(
                  label: 'report.html',
                  path: run.reportHtml,
                  onOpen: run.reportHtml == null ? null : onOpenReport,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: run.outputDir == null ? null : onReveal,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Reveal Folder'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete Run'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.palette.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _n(int? value) => value?.toString() ?? '—';

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: color ?? context.palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  const _ArtifactRow({required this.label, this.path, this.onOpen});

  final String label;
  final String? path;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final canOpen = onOpen != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            path == null
                ? Icons.insert_drive_file_outlined
                : Icons.description_outlined,
            size: 16,
            color: path == null
                ? context.palette.textMuted
                : context.palette.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: canOpen ? onOpen : null,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: canOpen
                            ? context.palette.accent
                            : context.palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        decoration: canOpen ? TextDecoration.underline : null,
                        decorationColor: context.palette.accent,
                      ),
                    ),
                    Text(
                      path ?? 'Not available',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
