import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_menu.dart';

class BranchSelector extends StatelessWidget {
  const BranchSelector({
    super.key,
    required this.branches,
    required this.currentBranch,
    required this.enabled,
    required this.onCheckout,
    required this.onCreateBranch,
    required this.onDeleteBranch,
  });

  final List<GitBranchInfo> branches;
  final String? currentBranch;
  final bool enabled;
  final ValueChanged<String> onCheckout;
  final ValueChanged<String> onCreateBranch;
  final ValueChanged<String> onDeleteBranch;

  @override
  Widget build(BuildContext context) {
    final label = currentBranch ?? 'No branch';
    if (!enabled) {
      return _BranchChip(label: label, enabled: false);
    }

    final localBranches =
        branches.where((branch) => !branch.remote).toList(growable: false);

    return PopupMenuButton<String>(
      tooltip: 'Switch branch',
      onSelected: (value) {
        if (value == '__create__') {
          _promptCreateBranch(context);
          return;
        }
        if (value.startsWith('__delete__|')) {
          final name = value.substring('__delete__|'.length);
          onDeleteBranch(name);
          return;
        }
        onCheckout(value);
      },
      itemBuilder: (context) {
        if (localBranches.isEmpty) {
          return [
            const AppPopupMenuItem<String>(
              enabled: false,
              child: Text('No branches'),
            ),
            const AppPopupMenuDivider(),
            const AppPopupMenuItem<String>(
              value: '__create__',
              child: Text('Create branch…'),
            ),
          ];
        }
        return [
          ...localBranches.map(
            (branch) => AppPopupMenuItem<String>(
              value: branch.name,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      branch.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight:
                            branch.current ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (branch.current)
                    const Icon(Icons.check, size: 14, color: AppColors.accent),
                  if (!branch.current && branch.name != currentBranch) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        onDeleteBranch(branch.name);
                      },
                      child: const Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const AppPopupMenuDivider(),
          const AppPopupMenuItem<String>(
            value: '__create__',
            child: Text('Create branch…'),
          ),
        ];
      },
      child: _BranchChip(label: label, enabled: true),
    );
  }

  Future<void> _promptCreateBranch(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Branch name',
            hintText: 'feature/login',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    onCreateBranch(name);
  }
}

class _BranchChip extends StatelessWidget {
  const _BranchChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.call_split,
            size: 14,
            color: enabled ? AppColors.textSecondary : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );
  }
}
