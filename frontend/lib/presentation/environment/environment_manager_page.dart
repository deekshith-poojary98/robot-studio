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
      color: context.palette.background,
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
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 18),
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
                Text('Sort by', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 10),
                DropdownButton<EnvironmentSort>(
                  value: sort,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.textPrimary,
                  ),
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
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: environments.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: context.palette.borderSubtle,
                    ),
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

class _EnvironmentRow extends StatefulWidget {
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
  State<_EnvironmentRow> createState() => _EnvironmentRowState();
}

class _EnvironmentRowState extends State<_EnvironmentRow> {
  bool _hovered = false;

  static final _actionStyle = TextButton.styleFrom(
    minimumSize: const Size(0, 28),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    final env = widget.environment;
    final palette = context.palette;
    final active = env.active;
    final selected = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: selected
            ? palette.accentSoft
            : _hovered
            ? palette.surfaceHover
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              env.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!env.available) ...[
                            const SizedBox(width: AppSpacing.sm),
                            const EnvironmentBadge(
                              label: 'Missing',
                              broken: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Python ${env.pythonVersion}  ·  '
                        'Robot ${env.robotVersion ?? '—'}  ·  '
                        '${env.packageCount} packages  ·  '
                        '${_formatDate(env.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: active ? null : widget.onActivate,
                  style: active
                      ? _actionStyle.copyWith(
                          foregroundColor: WidgetStatePropertyAll(
                            palette.success,
                          ),
                        )
                      : _actionStyle,
                  child: Text(active ? 'Active' : 'Activate'),
                ),
                TextButton(
                  onPressed: widget.onClone,
                  style: _actionStyle,
                  child: const Text('Clone'),
                ),
                TextButton(
                  onPressed: widget.onDelete,
                  style: _actionStyle,
                  child: const Text('Delete'),
                ),
              ],
            ),
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
