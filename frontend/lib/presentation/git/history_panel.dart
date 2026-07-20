import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    super.key,
    required this.commits,
    required this.selected,
    required this.detail,
    required this.isLoading,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<GitCommitInfo> commits;
  final GitCommitInfo? selected;
  final GitCommitDetailInfo? detail;
  final bool isLoading;
  final ValueChanged<GitCommitInfo> onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'History',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh history',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : commits.isEmpty
                  ? const Center(
                      child: Text(
                        'No commits yet',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 2,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: commits.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final commit = commits[index];
                              final isSelected = selected?.hash == commit.hash;
                              return Material(
                                color: isSelected
                                    ? AppColors.accentSoft
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.sm),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.sm),
                                  onTap: () => onSelect(commit),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              commit.shortHash,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                color: AppColors.accent,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                commit.author,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          commit.message,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatDate(commit.date),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 3,
                          child: detail == null
                              ? const Center(
                                  child: Text(
                                    'Select a commit to view details',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                )
                              : _CommitDetailView(detail: detail!),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _CommitDetailView extends StatelessWidget {
  const _CommitDetailView({required this.detail});

  final GitCommitDetailInfo detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          detail.message,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${detail.author} <${detail.email}>',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          detail.hash,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: AppColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Changed files',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        if (detail.files.isEmpty)
          const Text(
            'No files recorded',
            style: TextStyle(color: AppColors.textMuted),
          )
        else
          ...detail.files.map(
            (file) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  GitStatusBadge(status: file.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.path,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class GitStatusBadge extends StatelessWidget {
  const GitStatusBadge({super.key, required this.status});

  final GitFileStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      alignment: Alignment.center,
      child: Text(
        status.badge,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
