import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Confirm stopping an in-progress Robot run.
Future<bool> showStopExecutionDialog(
  BuildContext context, {
  String? suite,
  String? elapsedLabel,
  String? liveSuite,
  String? liveTest,
  String? liveKeyword,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final palette = dialogContext.palette;

      final suiteLabel = (suite != null && suite.isNotEmpty)
          ? suite
          : (liveSuite != null && liveSuite.isNotEmpty ? liveSuite : null);
      final testLabel = liveTest != null && liveTest.isNotEmpty
          ? liveTest
          : null;
      final keywordLabel = liveKeyword != null && liveKeyword.isNotEmpty
          ? liveKeyword
          : null;
      final hasProgress =
          suiteLabel != null || testLabel != null || keywordLabel != null;

      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Text('Stop execution?', style: theme.textTheme.titleLarge),
        content: SizedBox(
          width: AppDialogWidth.form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cancel the current Robot Framework run? Output so far is kept; '
                'the report may be incomplete.',
                style: theme.textTheme.bodyMedium,
              ),
              if (elapsedLabel != null && elapsedLabel.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Elapsed $elapsedLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
              if (hasProgress) ...[
                const SizedBox(height: AppSpacing.md),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: palette.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (suiteLabel != null)
                          _StopContextRow(label: 'Suite', value: suiteLabel),
                        if (testLabel != null) ...[
                          if (suiteLabel != null)
                            const SizedBox(height: AppSpacing.sm),
                          _StopContextRow(label: 'Test', value: testLabel),
                        ],
                        if (keywordLabel != null) ...[
                          if (suiteLabel != null || testLabel != null)
                            const SizedBox(height: AppSpacing.sm),
                          _StopContextRow(
                            label: 'Keyword',
                            value: keywordLabel,
                            emphasize: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Keep running',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: palette.error),
            child: const Text(
              'Stop',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

class _StopContextRow extends StatelessWidget {
  const _StopContextRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
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
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}
