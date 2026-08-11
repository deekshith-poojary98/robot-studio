import 'package:flutter/material.dart';

import '../../core/gateway/models/insights_info.dart';
import '../../core/theme/app_theme.dart';

Future<void> showInsightsFileTriageDialog(
  BuildContext context, {
  required InsightsFileRuns file,
  Future<String?> Function(String runId)? loadLastFailureName,
  VoidCallback? onOpenSource,
  VoidCallback? onOpenFailedTests,
  VoidCallback? onViewReport,
  VoidCallback? onRerun,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _InsightsFileTriageDialog(
      file: file,
      loadLastFailureName: loadLastFailureName,
      onOpenSource: onOpenSource,
      onOpenFailedTests: onOpenFailedTests,
      onViewReport: onViewReport,
      onRerun: onRerun,
    ),
  );
}

class _InsightsFileTriageDialog extends StatefulWidget {
  const _InsightsFileTriageDialog({
    required this.file,
    this.loadLastFailureName,
    this.onOpenSource,
    this.onOpenFailedTests,
    this.onViewReport,
    this.onRerun,
  });

  final InsightsFileRuns file;
  final Future<String?> Function(String runId)? loadLastFailureName;
  final VoidCallback? onOpenSource;
  final VoidCallback? onOpenFailedTests;
  final VoidCallback? onViewReport;
  final VoidCallback? onRerun;

  @override
  State<_InsightsFileTriageDialog> createState() =>
      _InsightsFileTriageDialogState();
}

class _InsightsFileTriageDialogState extends State<_InsightsFileTriageDialog> {
  String? _lastFailureName;
  bool _loadingName = false;

  @override
  void initState() {
    super.initState();
    final runId = widget.file.lastFailedRunId;
    final load = widget.loadLastFailureName;
    if (runId == null || runId.isEmpty || load == null) return;
    _loadingName = true;
    load(runId)
        .then((name) {
          if (!mounted) return;
          setState(() {
            _lastFailureName = name;
            _loadingName = false;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() => _loadingName = false);
        });
  }

  String get _fileLabel {
    final parts = widget.file.filePath.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? widget.file.filePath : parts.last;
  }

  void _run(VoidCallback? action) {
    Navigator.of(context).pop();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final file = widget.file;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(_fileLabel, style: Theme.of(context).textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              file.failed > 0
                  ? '${file.failed} ${file.failed == 1 ? 'failure' : 'failures'} across ${file.runs} ${file.runs == 1 ? 'run' : 'runs'}'
                  : '${file.runs} ${file.runs == 1 ? 'run' : 'runs'} · no failures',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loadingName)
              Text(
                'Loading last failure…',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              )
            else if (_lastFailureName != null && _lastFailureName!.isNotEmpty)
              Text(
                'Last failure: $_lastFailureName',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
              )
            else if (file.failed > 0)
              Text(
                'Open failed tests to inspect the last failure.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            const SizedBox(height: AppSpacing.md),
            if (widget.onOpenFailedTests != null && file.failed > 0)
              _TriageAction(
                label: 'Open failed tests',
                primary: true,
                onPressed: () => _run(widget.onOpenFailedTests),
              ),
            if (widget.onOpenSource != null)
              _TriageAction(
                label: 'Open source',
                onPressed: () => _run(widget.onOpenSource),
              ),
            if (widget.onViewReport != null)
              _TriageAction(
                label: 'View report',
                onPressed: () => _run(widget.onViewReport),
              ),
            if (widget.onRerun != null)
              _TriageAction(
                label: 'Rerun file',
                onPressed: () => _run(widget.onRerun),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TriageAction extends StatelessWidget {
  const _TriageAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: primary
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: style,
              ),
              child: Align(alignment: Alignment.centerLeft, child: Text(label)),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: style,
              ),
              child: Align(alignment: Alignment.centerLeft, child: Text(label)),
            ),
    );
  }
}
