import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';
import 'branch_selector.dart';
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
    this.onCheckoutBranch,
    this.onCreateBranch,
    this.onDeleteBranch,
    this.onAddRemote,
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
  final ValueChanged<String>? onCheckoutBranch;
  final ValueChanged<String>? onCreateBranch;
  final ValueChanged<String>? onDeleteBranch;
  final VoidCallback? onAddRemote;

  @override
  Widget build(BuildContext context) {
    final repository = status?.repository;
    final isRepository = repository?.isRepository ?? false;

    return ColoredBox(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            repository: repository,
            branches: branches,
            isLoading: isLoading,
            isBusy: isBusy,
            onRefresh: onRefresh,
            onFetch: onFetch,
            onPull: onPull,
            onPush: onPush,
            onCheckoutBranch: onCheckoutBranch,
            onCreateBranch: onCreateBranch,
            onDeleteBranch: onDeleteBranch,
            onAddRemote: onAddRemote,
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
                : _RepositoryBody(
                    changes: status?.changes ?? const [],
                    selectedFiles: selectedFiles,
                    selectedDiffFile: selectedDiffFile,
                    onToggleFile: onToggleFile,
                    onSelectDiffFile: onSelectDiffFile,
                    commitController: commitController,
                    isBusy: isBusy,
                    onCommitAll: onCommitAll,
                    onCommitSelected: onCommitSelected,
                    diff: diff,
                    isLoadingDiff: isLoadingDiff,
                    history: history,
                    selectedCommit: selectedCommit,
                    commitDetail: commitDetail,
                    isLoadingHistory: isLoadingHistory,
                    onSelectCommit: onSelectCommit,
                    onRefreshHistory: onRefreshHistory,
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
    required this.branches,
    required this.isLoading,
    required this.isBusy,
    required this.onRefresh,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
    this.onCheckoutBranch,
    this.onCreateBranch,
    this.onDeleteBranch,
    this.onAddRemote,
  });

  final GitRepositoryInfo? repository;
  final List<GitBranchInfo> branches;
  final bool isLoading;
  final bool isBusy;
  final VoidCallback onRefresh;
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;
  final ValueChanged<String>? onCheckoutBranch;
  final ValueChanged<String>? onCreateBranch;
  final ValueChanged<String>? onDeleteBranch;
  final VoidCallback? onAddRemote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final isRepo = repository?.isRepository ?? false;
    final dirty = !(repository?.clean ?? true);
    final remotes = repository?.remotes ?? const <GitRemoteInfo>[];
    final hasRemote = remotes.isNotEmpty;
    final primaryRemote = !hasRemote
        ? null
        : remotes.firstWhere(
            (remote) => remote.name == 'origin',
            orElse: () => remotes.first,
          );

    return ColoredBox(
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Source Control',
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                  ),
                ),
                if (isRepo) ...[
                  if (onCheckoutBranch != null &&
                      onCreateBranch != null &&
                      onDeleteBranch != null)
                    BranchSelector(
                      branches: branches,
                      currentBranch: repository?.branch,
                      enabled: !isBusy,
                      onCheckout: onCheckoutBranch!,
                      onCreateBranch: onCreateBranch!,
                      onDeleteBranch: onDeleteBranch!,
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusChip(
                    label: dirty ? 'Pending changes' : 'Up to date',
                    color: dirty ? palette.warning : palette.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (isRepo) ...[
                  _HeaderIcon(
                    tooltip: hasRemote ? 'Fetch' : 'Fetch (add a remote first)',
                    icon: Icons.cloud_download_outlined,
                    onPressed: isBusy || !hasRemote ? null : onFetch,
                  ),
                  _HeaderIcon(
                    tooltip: hasRemote ? 'Pull' : 'Pull (add a remote first)',
                    icon: Icons.download_outlined,
                    onPressed: isBusy || !hasRemote ? null : onPull,
                  ),
                  _HeaderIcon(
                    tooltip: hasRemote ? 'Push' : 'Push (add a remote first)',
                    icon: Icons.upload_outlined,
                    onPressed: isBusy || !hasRemote ? null : onPush,
                  ),
                ],
                _HeaderIcon(
                  tooltip: 'Refresh',
                  icon: Icons.refresh,
                  onPressed: isLoading || isBusy ? null : onRefresh,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _subtitle(repository),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (isRepo) ...[
              const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        hasRemote
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        size: 14,
                        color: hasRemote
                            ? palette.textSecondary
                            : palette.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          hasRemote
                              ? '${primaryRemote!.name} · ${primaryRemote.url}'
                              : 'No remote yet — add one to push this project.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: palette.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (onAddRemote != null)
                        TextButton(
                          onPressed: isBusy ? null : onAddRemote,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(hasRemote ? 'Edit remote' : 'Add remote'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitle(GitRepositoryInfo? repository) {
    if (repository == null || !repository.isRepository) {
      return 'Scoped to the open project — not a parent monorepo';
    }
    final branch = repository.branch ?? (repository.detached ? 'HEAD' : '—');
    final head = repository.head == null
        ? 'no commits'
        : repository.head!.length >= 7
        ? repository.head!.substring(0, 7)
        : repository.head!;
    final root = repository.root;
    if (root != null && root.isNotEmpty) {
      return '$branch · $head · $root';
    }
    return '$branch · $head';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 18),
    );
  }
}

class _RepositoryBody extends StatefulWidget {
  const _RepositoryBody({
    required this.changes,
    required this.selectedFiles,
    required this.selectedDiffFile,
    required this.onToggleFile,
    required this.onSelectDiffFile,
    required this.commitController,
    required this.isBusy,
    required this.onCommitAll,
    required this.onCommitSelected,
    required this.diff,
    required this.isLoadingDiff,
    required this.history,
    required this.selectedCommit,
    required this.commitDetail,
    required this.isLoadingHistory,
    required this.onSelectCommit,
    required this.onRefreshHistory,
  });

  final List<GitFileChangeInfo> changes;
  final Set<String> selectedFiles;
  final String? selectedDiffFile;
  final ValueChanged<String> onToggleFile;
  final ValueChanged<String> onSelectDiffFile;
  final TextEditingController commitController;
  final bool isBusy;
  final VoidCallback onCommitAll;
  final VoidCallback onCommitSelected;
  final GitDiffInfo? diff;
  final bool isLoadingDiff;
  final List<GitCommitInfo> history;
  final GitCommitInfo? selectedCommit;
  final GitCommitDetailInfo? commitDetail;
  final bool isLoadingHistory;
  final ValueChanged<GitCommitInfo> onSelectCommit;
  final VoidCallback onRefreshHistory;

  @override
  State<_RepositoryBody> createState() => _RepositoryBodyState();
}

class _RepositoryBodyState extends State<_RepositoryBody> {
  /// 0 = Diff, 1 = History
  int _rightTab = 0;

  @override
  void didUpdateWidget(covariant _RepositoryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opening a file diff should surface the Diff pane.
    if (widget.selectedDiffFile != null &&
        widget.selectedDiffFile != oldWidget.selectedDiffFile) {
      _rightTab = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: ColoredBox(
            color: context.palette.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ChangesView(
                    changes: widget.changes,
                    selectedFiles: widget.selectedFiles,
                    onToggleFile: widget.onToggleFile,
                    onSelectDiffFile: widget.onSelectDiffFile,
                    selectedDiffFile: widget.selectedDiffFile,
                  ),
                ),
                CommitPanel(
                  controller: widget.commitController,
                  enabled: true,
                  isBusy: widget.isBusy,
                  selectedCount: widget.selectedFiles.length,
                  totalCount: widget.changes.length,
                  onCommit: widget.onCommitAll,
                  onCommitSelected: widget.onCommitSelected,
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: context.palette.border),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    _PaneTab(
                      label: 'Diff',
                      selected: _rightTab == 0,
                      onTap: () => setState(() => _rightTab = 0),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _PaneTab(
                      label: 'History',
                      selected: _rightTab == 1,
                      onTap: () => setState(() => _rightTab = 1),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.palette.borderSubtle),
              Expanded(
                child: _rightTab == 0
                    ? DiffViewer(
                        diff: widget.diff,
                        isLoading: widget.isLoadingDiff,
                        fileLabel: widget.selectedDiffFile,
                      )
                    : HistoryPanel(
                        commits: widget.history,
                        selected: widget.selectedCommit,
                        detail: widget.commitDetail,
                        isLoading: widget.isLoadingHistory,
                        onSelect: widget.onSelectCommit,
                        onRefresh: widget.onRefreshHistory,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaneTab extends StatelessWidget {
  const _PaneTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfaceElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? palette.textPrimary : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
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
        title: 'Nothing to commit',
        message: 'Working tree is clean.',
        compact: true,
      );
    }

    final grouped = <GitFileStatus, List<GitFileChangeInfo>>{};
    for (final change in changes) {
      grouped.putIfAbsent(change.status, () => []).add(change);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Text(
                'CHANGES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${changes.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final status in GitFileStatus.values)
          if (grouped.containsKey(status)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                4,
              ),
              child: Text(
                '${status.label} · ${grouped[status]!.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: status.colorFor(context.palette),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...grouped[status]!.map(
              (change) => _ChangeRow(
                change: change,
                selected: selectedFiles.contains(change.path),
                active: selectedDiffFile == change.path,
                onToggle: () => onToggleFile(change.path),
                onOpenDiff: () => onSelectDiffFile(change.path),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _ChangeRow extends StatefulWidget {
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
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final path = widget.change.path.replaceAll('\\', '/');
    final parts = path.split('/');
    final name = parts.isEmpty ? path : parts.last;
    final dir = parts.length <= 1
        ? ''
        : parts.sublist(0, parts.length - 1).join('/');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.active
            ? palette.accentSoft
            : _hover
            ? palette.surfaceHover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.xs),
          onTap: widget.onOpenDiff,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Transform.scale(
                    scale: 0.78,
                    child: Checkbox(
                      value: widget.selected,
                      onChanged: (_) => widget.onToggle(),
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      splashRadius: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GitStatusBadge(status: widget.change.status),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: palette.textPrimary,
                        ),
                      ),
                      if (dir.isNotEmpty)
                        Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the loaded Source Control body: changes + commit (left) | pane (right).
class _SourceControlSkeleton extends StatelessWidget {
  const _SourceControlSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    _SkeletonBlock(width: 44, height: 22),
                    SizedBox(width: 8),
                    _SkeletonBlock(width: 64, height: 22),
                  ],
                ),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonBlock(width: 110, height: 10),
          SizedBox(height: 8),
          _SkeletonBlock(height: 52),
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
