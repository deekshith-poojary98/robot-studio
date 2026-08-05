import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';
import 'commit_panel.dart';
import 'diff_viewer.dart';
import 'history_panel.dart';

class SourceControlPage extends StatelessWidget {
  const SourceControlPage({
    super.key,
    required this.status,
    required this.branches,
    required this.history,
    required this.selectedCommit,
    required this.commitDetail,
    required this.diff,
    required this.selectedFiles,
    required this.selectedDiffFile,
    required this.commitController,
    required this.isLoading,
    required this.isBusy,
    required this.isLoadingHistory,
    required this.isLoadingDiff,
    required this.onRefresh,
    required this.onInit,
    required this.onToggleFile,
    required this.onSelectDiffFile,
    required this.onCommitAll,
    required this.onCommitSelected,
    required this.onSelectCommit,
    required this.onRefreshHistory,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
  });

  final GitStatusInfo? status;
  final List<GitBranchInfo> branches;
  final List<GitCommitInfo> history;
  final GitCommitInfo? selectedCommit;
  final GitCommitDetailInfo? commitDetail;
  final GitDiffInfo? diff;
  final Set<String> selectedFiles;
  final String? selectedDiffFile;
  final TextEditingController commitController;
  final bool isLoading;
  final bool isBusy;
  final bool isLoadingHistory;
  final bool isLoadingDiff;
  final VoidCallback onRefresh;
  final VoidCallback onInit;
  final ValueChanged<String> onToggleFile;
  final ValueChanged<String> onSelectDiffFile;
  final VoidCallback onCommitAll;
  final VoidCallback onCommitSelected;
  final ValueChanged<GitCommitInfo> onSelectCommit;
  final VoidCallback onRefreshHistory;
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    final repository = status?.repository;
    final isRepository = repository?.isRepository ?? false;

    return Container(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            repository: repository,
            isLoading: isLoading,
            isBusy: isBusy,
            onRefresh: onRefresh,
            onFetch: onFetch,
            onPull: onPull,
            onPush: onPush,
          ),
          const Divider(height: 1),
          Expanded(
            child: isLoading && status == null
                ? const _SourceControlSkeleton()
                : !isRepository
                ? EmptyState(
                    icon: Icons.source_outlined,
                    title: 'No Git repository in this project',
                    message:
                        'Source Control always uses the open Robot Studio project. '
                        'Initialize Git here, or open the parent folder as the project '
                        'if you intentionally want that repository.',
                    actionLabel: isBusy
                        ? null
                        : 'Initialize Git in this project',
                    onAction: isBusy ? null : onInit,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ChangesView(
                                changes: status?.changes ?? const [],
                                selectedFiles: selectedFiles,
                                onToggleFile: onToggleFile,
                                onSelectDiffFile: onSelectDiffFile,
                                selectedDiffFile: selectedDiffFile,
                              ),
                            ),
                            CommitPanel(
                              controller: commitController,
                              enabled: isRepository,
                              isBusy: isBusy,
                              selectedCount: selectedFiles.length,
                              totalCount: status?.changes.length ?? 0,
                              onCommit: onCommitAll,
                              onCommitSelected: onCommitSelected,
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 4,
                        child: selectedDiffFile != null
                            ? DiffViewer(
                                diff: diff,
                                isLoading: isLoadingDiff,
                                fileLabel: selectedDiffFile,
                              )
                            : HistoryPanel(
                                commits: history,
                                selected: selectedCommit,
                                detail: commitDetail,
                                isLoading: isLoadingHistory,
                                onSelect: onSelectCommit,
                                onRefresh: onRefreshHistory,
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.repository,
    required this.isLoading,
    required this.isBusy,
    required this.onRefresh,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
  });

  final GitRepositoryInfo? repository;
  final bool isLoading;
  final bool isBusy;
  final VoidCallback onRefresh;
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Source Control',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(repository),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Wrap, not horizontal scroll: actions must stay reachable when the
          // window is narrow.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (repository?.isRepository ?? false) ...[
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onFetch,
                  icon: const Icon(Icons.cloud_download_outlined, size: 16),
                  label: const Text('Fetch'),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onPull,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Pull'),
                ),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : onPush,
                  icon: const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('Push'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: isLoading || isBusy ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(GitRepositoryInfo? repository) {
    if (repository == null || !repository.isRepository) {
      return 'Scoped to the open project — not a parent monorepo';
    }
    final branch = repository.branch ?? (repository.detached ? 'HEAD' : '—');
    final head = repository.head?.substring(0, 7) ?? 'no commits';
    final dirty = repository.clean ? 'clean' : 'dirty';
    final root = repository.root;
    if (root != null && root.isNotEmpty) {
      return '$branch · $head · $dirty · $root';
    }
    return '$branch · $head · $dirty';
  }
}

class _ChangesView extends StatelessWidget {
  const _ChangesView({
    required this.changes,
    required this.selectedFiles,
    required this.onToggleFile,
    required this.onSelectDiffFile,
    required this.selectedDiffFile,
  });

  final List<GitFileChangeInfo> changes;
  final Set<String> selectedFiles;
  final ValueChanged<String> onToggleFile;
  final ValueChanged<String> onSelectDiffFile;
  final String? selectedDiffFile;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No changes',
        message: 'Your working tree is clean.',
        compact: true,
      );
    }

    final grouped = <GitFileStatus, List<GitFileChangeInfo>>{};
    for (final change in changes) {
      grouped.putIfAbsent(change.status, () => []).add(change);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Changes', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        for (final status in GitFileStatus.values)
          if (grouped.containsKey(status)) ...[
            Text(
              status.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: status.colorFor(context.palette),
              ),
            ),
            const SizedBox(height: 6),
            ...grouped[status]!.map(
              (change) => _ChangeRow(
                change: change,
                selected: selectedFiles.contains(change.path),
                active: selectedDiffFile == change.path,
                onToggle: () => onToggleFile(change.path),
                onOpenDiff: () => onSelectDiffFile(change.path),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.change,
    required this.selected,
    required this.active,
    required this.onToggle,
    required this.onOpenDiff,
  });

  final GitFileChangeInfo change;
  final bool selected;
  final bool active;
  final VoidCallback onToggle;
  final VoidCallback onOpenDiff;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? context.palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: onOpenDiff,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              GitStatusBadge(status: change.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  change.path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors the loaded Source Control body: changes + commit (left) | history (right).
class _SourceControlSkeleton extends StatelessWidget {
  const _SourceControlSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SkeletonList(
                  rows: 6,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                ),
              ),
              _CommitPanelSkeleton(),
            ],
          ),
        ),
        VerticalDivider(width: 1),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SkeletonBlock(width: 72, height: 12),
              ),
              Divider(height: 1),
              Expanded(
                child: SkeletonList(rows: 7, padding: EdgeInsets.all(16)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommitPanelSkeleton extends StatelessWidget {
  const _CommitPanelSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonBlock(width: 110, height: 10),
          SizedBox(height: 8),
          _SkeletonBlock(height: 72),
          SizedBox(height: 12),
          Row(
            children: [
              _SkeletonBlock(width: 100, height: 28),
              SizedBox(width: 8),
              _SkeletonBlock(width: 130, height: 28),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: context.palette.surfaceHover,
          borderRadius: BorderRadius.circular(AppRadii.xs),
        ),
      ),
    );
  }
}
