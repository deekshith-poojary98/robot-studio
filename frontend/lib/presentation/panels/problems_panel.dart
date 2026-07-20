import 'package:flutter/material.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

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
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (diagnostics.isEmpty) {
      return Center(
        child: Text(
          'No problems detected in the workspace.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: diagnostics.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderSubtle),
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
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            item.locationLabel,
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
