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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Commit Message', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled && !isBusy,
            maxLines: 4,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: 'Describe your changes…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasMessage = value.text.trim().isNotEmpty;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: enabled && !isBusy && hasMessage
                        ? onCommit
                        : null,
                    icon: isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Commit All'),
                  ),
                  OutlinedButton(
                    onPressed:
                        enabled && !isBusy && hasMessage && selectedCount > 0
                        ? onCommitSelected
                        : null,
                    child: Text(
                      selectedCount > 0
                          ? 'Commit Selected ($selectedCount)'
                          : 'Commit Selected',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      totalCount == 0
                          ? 'No changes'
                          : '$totalCount changed file'
                                '${totalCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
