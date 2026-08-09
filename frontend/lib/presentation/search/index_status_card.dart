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
    this.compact = false,
  });

  final IndexStatusInfo? status;
  final bool isLoading;
  final VoidCallback? onRebuild;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = status;
    if (compact) {
      return _buildCompact(context, data);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Index Status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (data != null)
                StatusBadge(
                  label: data.state.toUpperCase(),
                  filled: data.state == 'ready',
                  dotColor: data.state == 'ready'
                      ? context.palette.success
                      : data.state == 'indexing'
                      ? context.palette.accent
                      : context.palette.textMuted,
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
              'Open a project to build the symbol index.',
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

  Widget _buildCompact(BuildContext context, IndexStatusInfo? data) {
    return Row(
      children: [
        Expanded(
          child: Text(
            data == null
                ? (isLoading ? 'Indexing…' : 'Index not ready')
                : '${data.keywordsIndexed} keywords · ${data.filesIndexed} files',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
        ),
        if (onRebuild != null)
          IconButton(
            tooltip: 'Rebuild index',
            onPressed: isLoading ? null : onRebuild,
            icon: const Icon(Icons.refresh, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
      ],
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
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: context.palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
