import 'package:flutter/material.dart';

import '../../core/gateway/models/run_failure_info.dart';
import '../../core/theme/app_theme.dart';

/// Post-run Failed Tests list — Jump to Source + Re-run Test.
class FailedTestsPanel extends StatelessWidget {
  const FailedTestsPanel({
    super.key,
    required this.failures,
    this.isLoading = false,
    this.embedded = false,
    this.onJumpToSource,
    this.onRerunTest,
  });

  final List<RunTestFailureInfo> failures;
  final bool isLoading;

  /// When true, omit the chrome header/dividers (parent supplies a section title).
  final bool embedded;
  final void Function(RunTestFailureInfo failure)? onJumpToSource;
  final void Function(RunTestFailureInfo failure)? onRerunTest;

  @override
  Widget build(BuildContext context) {
    if (isLoading && failures.isEmpty) {
      return _FailedTestsSkeleton(dense: embedded);
    }
    if (failures.isEmpty) {
      if (!embedded) return const SizedBox.shrink();
      return Text(
        'No failure details available for this run.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
      );
    }

    final theme = Theme.of(context);
    final list = failures.length > 4
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: embedded ? 280 : 220),
            child: ListView.separated(
              shrinkWrap: true,
              physics: embedded
                  ? const ClampingScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                vertical: embedded ? 0 : AppSpacing.sm,
              ),
              itemCount: failures.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final failure = failures[index];
                return _FailureRow(
                  failure: failure,
                  dense: embedded,
                  onJump: onJumpToSource == null || !failure.canJump
                      ? null
                      : () => onJumpToSource!(failure),
                  onRerun: onRerunTest == null || !failure.canJump
                      ? null
                      : () => onRerunTest!(failure),
                );
              },
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < failures.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _FailureRow(
                  failure: failures[index],
                  dense: embedded,
                  onJump: onJumpToSource == null || !failures[index].canJump
                      ? null
                      : () => onJumpToSource!(failures[index]),
                  onRerun: onRerunTest == null || !failures[index].canJump
                      ? null
                      : () => onRerunTest!(failures[index]),
                ),
              ],
            ],
          );

    if (embedded) return list;

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
              Icon(Icons.error_outline, size: 16, color: context.palette.error),
              const SizedBox(width: AppSpacing.sm),
              Text('Failed Tests', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${failures.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.palette.error,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        list,
        const Divider(height: 1),
      ],
    );
  }
}

/// Quiet placeholder matching a failure row — no accent spinner flash.
class _FailedTestsSkeleton extends StatelessWidget {
  const _FailedTestsSkeleton({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('failed-tests-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const Divider(height: 1),
          _SkeletonFailureRow(dense: dense),
        ],
      ],
    );
  }
}

class _SkeletonFailureRow extends StatelessWidget {
  const _SkeletonFailureRow({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bone = context.palette.surfaceHover;
    Widget bar(double widthFactor, double height) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: bone,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        dense ? 0 : AppSpacing.lg,
        AppSpacing.sm,
        dense ? 0 : AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(0.42, 12),
          const SizedBox(height: AppSpacing.sm),
          bar(0.78, 10),
          const SizedBox(height: AppSpacing.xs),
          bar(0.55, 9),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Container(
                width: 96,
                height: 22,
                decoration: BoxDecoration(
                  color: bone,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 84,
                height: 22,
                decoration: BoxDecoration(
                  color: bone,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({
    required this.failure,
    this.dense = false,
    this.onJump,
    this.onRerun,
  });

  final RunTestFailureInfo failure;
  final bool dense;
  final VoidCallback? onJump;
  final VoidCallback? onRerun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = failure.line == null
        ? failure.source
        : '${failure.source}:${failure.line}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        dense ? 0 : AppSpacing.lg,
        AppSpacing.sm,
        dense ? 0 : AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            failure.name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: context.palette.textPrimary,
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
                color: context.palette.error,
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
                color: context.palette.textMuted,
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
