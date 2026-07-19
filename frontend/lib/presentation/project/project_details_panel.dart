import 'package:flutter/material.dart';

import '../../core/gateway/models/project_info.dart';
import '../../core/theme/app_theme.dart';

IconData iconForProjectType(ProjectType type) {
  return switch (type) {
    ProjectType.browser => Icons.language,
    ProjectType.api => Icons.api_outlined,
    ProjectType.selenium => Icons.web_asset,
    ProjectType.empty => Icons.folder_open_outlined,
    ProjectType.imported => Icons.link,
  };
}

class ProjectDetailsPanel extends StatelessWidget {
  const ProjectDetailsPanel({super.key, required this.project});

  final ProjectInfo project;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  iconForProjectType(project.type),
                  size: 28,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 20,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailRow(label: 'Type', value: project.type.label),
            _DetailRow(label: 'Location', value: project.path),
            _DetailRow(
              label: 'Created',
              value: _formatDate(project.createdAt),
            ),
          ],
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
