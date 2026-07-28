import 'package:flutter/material.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';

class ProblemsPanel extends StatelessWidget {
  const ProblemsPanel({
    super.key,
    required this.diagnostics,
    required this.onSelect,
    this.isLoading = false,
  });

  final List<DiagnosticInfo> diagnostics;
  final ValueChanged<DiagnosticInfo> onSelect;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SkeletonList(rows: 5);
    }
    if (diagnostics.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No problems',
        message: 'Diagnostics appear here as you edit .robot files.',
        compact: true,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: diagnostics.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.borderSubtle),
      itemBuilder: (context, index) {
        final item = diagnostics[index];
        return ListTile(
          key: Key('problem-${item.filePath}-${item.line}-$index'),
          dense: true,
          leading: Icon(
            _iconFor(item.severity),
            size: 16,
            color: _colorFor(item.severity),
          ),
          title: Text(
            item.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            item.locationLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => onSelect(item),
        );
      },
    );
  }

  IconData _iconFor(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.error => Icons.error_outline,
      DiagnosticSeverity.warning => Icons.warning_amber_outlined,
      DiagnosticSeverity.information => Icons.info_outline,
    };
  }

  Color _colorFor(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.error => AppColors.error,
      DiagnosticSeverity.warning => AppColors.warning,
      DiagnosticSeverity.information => AppColors.accent,
    };
  }
}
