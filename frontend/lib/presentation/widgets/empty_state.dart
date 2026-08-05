import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One empty-state language for the whole app: why you are here, what to do
/// next, and a single obvious action. Use [compact] inside the 280px side rail.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$title. $message',
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 260 : 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: compact ? 28 : 36,
                  color: context.palette.textMuted,
                ),
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.md + 2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: compact
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                if (actionLabel != null && onAction != null) ...[
                  SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
                if (secondaryActionLabel != null &&
                    onSecondaryAction != null) ...[
                  const SizedBox(height: AppSpacing.xs + 2),
                  TextButton(
                    onPressed: onSecondaryAction,
                    child: Text(secondaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
