import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';

class IndexStatusCard extends StatelessWidget {
  const IndexStatusCard({
    super.key,
    required this.status,
    this.isLoading = false,
    this.onRebuild,
  });

  final IndexStatusInfo? status;
  final bool isLoading;
  final VoidCallback? onRebuild;

  @override
  Widget build(BuildContext context) {
    final data = status;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Index Status', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (data != null)
                StatusBadge(
                  label: data.state.toUpperCase(),
                  filled: data.state == 'ready',
                  dotColor: data.state == 'ready'
                      ? AppColors.success
                      : data.state == 'indexing'
                          ? AppColors.accent
                          : AppColors.textMuted,
                ),
              if (onRebuild != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isLoading ? null : onRebuild,
                  child: const Text('Rebuild'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading && data == null)
            const Center(child: CircularProgressIndicator())
          else if (data == null)
            Text(
              'Open a workspace to build the symbol index.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(label: 'Files', value: '${data.filesIndexed}'),
                _Metric(label: 'Keywords', value: '${data.keywordsIndexed}'),
                _Metric(label: 'Libraries', value: '${data.librariesIndexed}'),
                _Metric(label: 'Variables', value: '${data.variablesIndexed}'),
                _Metric(label: 'Last Indexed', value: data.lastIndexedLabel),
              ],
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
