import 'package:flutter/material.dart';

import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';

/// Post-run Failed Tests list — Jump to Source + Re-run Test.
class FailedTestsPanel extends StatelessWidget {
  const FailedTestsPanel({
    super.key,
    required this.failures,
    this.isLoading = false,
    this.onJumpToSource,
    this.onRerunTest,
  });

  final List<RunTestFailureInfo> failures;
  final bool isLoading;
  final void Function(RunTestFailureInfo failure)? onJumpToSource;
  final void Function(RunTestFailureInfo failure)? onRerunTest;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (failures.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
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
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Failed Tests',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${failures.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: failures.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final failure = failures[index];
              return _FailureRow(
                failure: failure,
                onJump: onJumpToSource == null || !failure.canJump
                    ? null
                    : () => onJumpToSource!(failure),
                onRerun: onRerunTest == null || !failure.canJump
                    ? null
                    : () => onRerunTest!(failure),
              );
            },
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({
    required this.failure,
    this.onJump,
    this.onRerun,
  });

  final RunTestFailureInfo failure;
  final VoidCallback? onJump;
  final VoidCallback? onRerun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = failure.line == null
        ? failure.source
        : '${failure.source}:${failure.line}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            failure.name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (failure.message.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              failure.message.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
          if (location.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontFamily: 'Menlo',
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: onJump,
                icon: const Icon(Icons.subdirectory_arrow_right, size: 16),
                label: const Text('Jump to Source'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: onRerun,
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('Re-run Test'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
