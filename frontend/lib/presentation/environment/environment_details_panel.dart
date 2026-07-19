import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/theme/app_theme.dart';
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
      color: AppColors.background,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.memory_outlined,
                    size: 28,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      env.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 20,
                          ),
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
              _DetailRow(label: 'Python Version', value: env.pythonVersion),
              _DetailRow(
                label: 'Robot Version',
                value: env.robotVersion ?? 'Not installed',
              ),
              _DetailRow(label: 'Interpreter Path', value: env.pythonExecutable),
              _DetailRow(label: 'Pip Path', value: env.pipExecutable),
              _DetailRow(
                label: 'Robot Path',
                value: env.robotExecutable ?? '—',
              ),
              _DetailRow(label: 'Platform', value: env.platform ?? '—'),
              _DetailRow(
                label: 'Architecture',
                value: env.architecture ?? '—',
              ),
              _DetailRow(
                label: 'Package Count',
                value: env.packageCount.toString(),
              ),
              _DetailRow(label: 'Location', value: env.path),
              _DetailRow(
                label: 'Created Date',
                value: _formatDate(env.createdAt),
              ),
              _DetailRow(
                label: 'Status',
                value: env.active ? 'Active' : 'Inactive',
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
