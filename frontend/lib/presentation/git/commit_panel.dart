import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class CommitPanel extends StatelessWidget {
  const CommitPanel({
    super.key,
    required this.controller,
    required this.onCommit,
    required this.onCommitSelected,
    required this.enabled,
    required this.isBusy,
    required this.selectedCount,
    required this.totalCount,
  });

  final TextEditingController controller;
  final VoidCallback onCommit;
  final VoidCallback onCommitSelected;
  final bool enabled;
  final bool isBusy;
  final int selectedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'COMMIT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              enabled: enabled && !isBusy,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Message…',
                isDense: true,
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  borderSide: BorderSide(color: palette.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  borderSide: BorderSide(color: palette.borderSubtle),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasMessage = value.text.trim().isNotEmpty;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: enabled && !isBusy && hasMessage
                                ? onCommit
                                : null,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: isBusy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Commit All'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                enabled &&
                                    !isBusy &&
                                    hasMessage &&
                                    selectedCount > 0
                                ? onCommitSelected
                                : null,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(
                              selectedCount > 0
                                  ? 'Selected ($selectedCount)'
                                  : 'Selected',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      totalCount == 0
                          ? 'No changes to commit'
                          : '$totalCount file${totalCount == 1 ? '' : 's'} changed',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
