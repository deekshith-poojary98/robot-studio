import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/detail_property_table.dart';
import '../widgets/status_badge.dart';

class EnvironmentDetailsPanel extends StatelessWidget {
  const EnvironmentDetailsPanel({
    super.key,
    required this.environment,
    this.onActivate,
    this.onClone,
    this.onDelete,
    this.onManage,
  });

  final EnvironmentInfo environment;
  final VoidCallback? onActivate;
  final VoidCallback? onClone;
  final VoidCallback? onDelete;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final env = environment;
    return Container(
      color: context.palette.background,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.memory_outlined,
                    size: 28,
                    color: context.palette.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      env.name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 20),
                    ),
                  ),
                  if (env.active)
                    const EnvironmentBadge(label: 'Active', active: true)
                  else
                    const EnvironmentBadge(label: 'Inactive', active: false),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!env.active && onActivate != null)
                    FilledButton(
                      onPressed: onActivate,
                      child: const Text('Activate'),
                    ),
                  if (onClone != null)
                    OutlinedButton(
                      onPressed: onClone,
                      child: const Text('Clone'),
                    ),
                  if (onDelete != null)
                    OutlinedButton(
                      onPressed: onDelete,
                      child: const Text('Delete'),
                    ),
                  if (onManage != null)
                    TextButton(
                      onPressed: onManage,
                      child: const Text('Open Manager'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              DetailPropertyTable(
                rows: [
                  DetailPropertyRow(
                    label: 'Python version',
                    value: env.pythonVersion,
                  ),
                  DetailPropertyRow(
                    label: 'Robot version',
                    value: env.robotVersion ?? 'Not installed',
                  ),
                  DetailPropertyRow(
                    label: 'Interpreter path',
                    value: env.pythonExecutable,
                  ),
                  DetailPropertyRow(
                    label: 'Pip path',
                    value: env.pipExecutable,
                  ),
                  DetailPropertyRow(
                    label: 'Robot path',
                    value: env.robotExecutable ?? '—',
                  ),
                  DetailPropertyRow(
                    label: 'Platform',
                    value: env.platform ?? '—',
                  ),
                  DetailPropertyRow(
                    label: 'Architecture',
                    value: env.architecture ?? '—',
                  ),
                  DetailPropertyRow(
                    label: 'Package count',
                    value: env.packageCount.toString(),
                  ),
                  DetailPropertyRow(label: 'Location', value: env.path),
                  DetailPropertyRow(
                    label: 'Created date',
                    value: _formatDate(env.createdAt),
                  ),
                  DetailPropertyRow(
                    label: 'Status',
                    value: env.active ? 'Active' : 'Inactive',
                  ),
                ],
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
