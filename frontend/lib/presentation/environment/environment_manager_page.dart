import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_badge.dart';

class EnvironmentManagerPage extends StatelessWidget {
  const EnvironmentManagerPage({
    super.key,
    required this.environments,
    required this.isLoading,
    required this.sort,
    required this.selected,
    required this.onSortChanged,
    required this.onSelect,
    required this.onCreate,
    required this.onImport,
    required this.onActivate,
    required this.onClone,
    required this.onDelete,
  });

  final List<EnvironmentInfo> environments;
  final bool isLoading;
  final EnvironmentSort sort;
  final EnvironmentInfo? selected;
  final ValueChanged<EnvironmentSort> onSortChanged;
  final ValueChanged<EnvironmentInfo> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final ValueChanged<EnvironmentInfo> onActivate;
  final ValueChanged<EnvironmentInfo> onClone;
  final ValueChanged<EnvironmentInfo> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Environment Manager',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage Python virtual environments for this project.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Import'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text(
                  'Sort by',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 10),
                DropdownButton<EnvironmentSort>(
                  value: sort,
                  underline: const SizedBox.shrink(),
                  items: EnvironmentSort.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: isLoading
                ? const SkeletonList(rows: 5)
                : environments.isEmpty
                    ? EmptyState(
                        icon: Icons.memory_outlined,
                        title: 'No environments yet',
                        message:
                            'Create a virtual environment or import an existing one.',
                        actionLabel: 'Create Environment',
                        onAction: onCreate,
                        secondaryActionLabel: 'Import…',
                        onSecondaryAction: onImport,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: environments.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final env = environments[index];
                          final isSelected = selected?.id == env.id;
                          return _EnvironmentRow(
                            environment: env,
                            selected: isSelected,
                            onTap: () => onSelect(env),
                            onActivate: () => onActivate(env),
                            onClone: () => onClone(env),
                            onDelete: () => onDelete(env),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentRow extends StatelessWidget {
  const _EnvironmentRow({
    required this.environment,
    required this.selected,
    required this.onTap,
    required this.onActivate,
    required this.onClone,
    required this.onDelete,
  });

  final EnvironmentInfo environment;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final env = environment;
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          env.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (env.active)
                          const EnvironmentBadge(label: 'Active', active: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Python ${env.pythonVersion}  ·  '
                      'Robot ${env.robotVersion ?? '—'}  ·  '
                      '${env.packageCount} packages  ·  '
                      '${_formatDate(env.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!env.active)
                TextButton(
                  onPressed: onActivate,
                  child: const Text('Activate'),
                ),
              TextButton(
                onPressed: onClone,
                child: const Text('Clone'),
              ),
              TextButton(
                onPressed: onDelete,
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
