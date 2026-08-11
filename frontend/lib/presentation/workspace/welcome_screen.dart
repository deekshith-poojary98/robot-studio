import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/report_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../../core/theme/app_theme.dart';
import '../search/index_status_card.dart';
import '../widgets/explorer_tree.dart';
import '../widgets/info_card.dart';
import '../widgets/status_badge.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.recentWorkspaces,
    required this.recentProjects,
    required this.isLoadingRecent,
    required this.onNewWorkspace,
    required this.onOpenWorkspace,
    required this.onOpenProject,
    required this.onOpenRecentWorkspace,
    required this.onOpenRecentProject,
    this.onNewProject,
    this.onImportProject,
    this.recentRuns = const [],
    this.runningStatus,
    this.lastRunLabel,
    this.dashboard,
    this.workspaceOpen = false,
    this.indexStatus,
    this.isLoadingIndexStatus = false,
    this.onRebuildIndex,
    this.recentFiles = const [],
    this.openEditors = const [],
    this.onOpenRecentFile,
    this.onContinueWorking,
    this.backendUnavailable = false,
    this.showBranding = true,
  });

  final List<WorkspaceInfo> recentWorkspaces;
  final List<ProjectInfo> recentProjects;
  final bool isLoadingRecent;
  final VoidCallback onNewWorkspace;
  final VoidCallback onOpenWorkspace;
  final VoidCallback onOpenProject;
  final ValueChanged<WorkspaceInfo> onOpenRecentWorkspace;
  final ValueChanged<ProjectInfo> onOpenRecentProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onImportProject;
  final List<ExecutionInfo> recentRuns;
  final ExecutionStatus? runningStatus;
  final String? lastRunLabel;
  final DashboardSummary? dashboard;
  final bool workspaceOpen;
  final IndexStatusInfo? indexStatus;
  final bool isLoadingIndexStatus;
  final VoidCallback? onRebuildIndex;
  final List<String> recentFiles;
  final List<String> openEditors;
  final ValueChanged<String>? onOpenRecentFile;
  final VoidCallback? onContinueWorking;
  final bool backendUnavailable;
  final bool showBranding;

  bool get _showDashboardSection => dashboard != null || workspaceOpen;
  bool get _showEditorSections =>
      recentFiles.isNotEmpty || openEditors.isNotEmpty;
  bool get _showIndexStatusSection =>
      workspaceOpen || indexStatus != null || isLoadingIndexStatus;

  @override
  Widget build(BuildContext context) {
    const horizontalPad = AppSpacing.xl;
    const verticalPad = AppSpacing.xl;

    return Container(
      color: context.palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: verticalPad,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - verticalPad * 2),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showBranding) ...[
                        Center(
                          child: Image.asset(
                            Theme.of(context).brightness == Brightness.dark
                                ? 'assets/branding/logo-wordmark.png'
                                : 'assets/branding/logo-wordmark-light.png',
                            key: const Key('welcome.wordmark'),
                            height: 72,
                            fit: BoxFit.contain,
                            cacheHeight: 144,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            semanticLabel: 'Robot Studio',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        'Robot Framework development, project first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (backendUnavailable) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          key: const Key('welcome.backend-unavailable'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: context.palette.surface,
                            border: Border.all(
                              color: context.palette.borderSubtle,
                            ),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            kReleaseMode
                                ? 'Robot Studio could not start its backend service. '
                                      'Quit and reopen the app, or reinstall Robot Studio.'
                                : 'Backend unavailable. Start it with: '
                                      'make backend   (or: python -m robot_studio.main)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.palette.textSecondary,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      _ActionTileRow(
                        tiles: [
                          QuickActionTile(
                            icon: Icons.note_add_outlined,
                            label: 'New Project',
                            subtitle: 'Create a Robot Framework project',
                            enabled: onNewProject != null,
                            disabledTooltip: 'New Project is unavailable',
                            onTap: onNewProject ?? () {},
                          ),
                          QuickActionTile(
                            icon: Icons.folder_special_outlined,
                            label: 'Open Project',
                            subtitle: 'Open any Robot Framework project folder',
                            onTap: onOpenProject,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      InfoCard(
                        title: 'Recent Projects',
                        child: _RecentProjectsBody(
                          projects: recentProjects,
                          isLoading: isLoadingRecent,
                          onOpen: onOpenRecentProject,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Advanced',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Workspaces are optional multi-project containers.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionTileRow(
                        tiles: [
                          QuickActionTile(
                            icon: Icons.folder_open_outlined,
                            label: 'Open Workspace',
                            subtitle:
                                'Open an existing multi-project workspace',
                            onTap: onOpenWorkspace,
                          ),
                          QuickActionTile(
                            icon: Icons.add,
                            label: 'New Workspace',
                            subtitle: 'Create a multi-project workspace',
                            onTap: onNewWorkspace,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      InfoCard(
                        title: 'Recent Workspaces',
                        child: _RecentWorkspacesBody(
                          workspaces: recentWorkspaces,
                          isLoading: isLoadingRecent,
                          onOpen: onOpenRecentWorkspace,
                        ),
                      ),
                      if (_showEditorSections) ...[
                        const SizedBox(height: AppSpacing.md),
                        LayoutBuilder(
                          builder: (context, sectionConstraints) {
                            final sideBySide =
                                sectionConstraints.maxWidth > 560;
                            final recent = InfoCard(
                              title: 'Recent Files',
                              child: _RecentFilesBody(
                                paths: recentFiles,
                                onOpen: onOpenRecentFile,
                              ),
                            );
                            final editors = InfoCard(
                              title: 'Open Editors',
                              child: _OpenEditorsBody(
                                paths: openEditors,
                                onOpen: onOpenRecentFile,
                              ),
                            );

                            if (sideBySide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: recent),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(child: editors),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                recent,
                                const SizedBox(height: AppSpacing.md),
                                editors,
                              ],
                            );
                          },
                        ),
                        if (onContinueWorking != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: FilledButton.icon(
                              onPressed: onContinueWorking,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Continue Working'),
                            ),
                          ),
                        ],
                      ],
                      if (_showIndexStatusSection) ...[
                        const SizedBox(height: AppSpacing.md),
                        IndexStatusCard(
                          status: indexStatus,
                          isLoading: isLoadingIndexStatus,
                          onRebuild: onRebuildIndex,
                        ),
                      ],
                      if (_showDashboardSection) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoCard(
                          title: 'Run Dashboard',
                          child: _DashboardBody(dashboard: dashboard),
                        ),
                      ] else if (recentRuns.isNotEmpty ||
                          runningStatus != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        InfoCard(
                          title: 'Recent Runs',
                          child: _RecentRunsBody(
                            runs: recentRuns,
                            runningStatus: runningStatus,
                            lastRunLabel: lastRunLabel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionTileRow extends StatelessWidget {
  const _ActionTileRow({required this.tiles});

  final List<QuickActionTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 420;
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({this.dashboard});

  final DashboardSummary? dashboard;

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Loading run statistics…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    if (data.totalRuns == 0) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No runs yet — run a suite to see results here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DashboardMetric(label: 'Total Runs', value: '${data.totalRuns}'),
              _DashboardMetric(label: 'Pass Rate', value: data.passRateLabel),
              _DashboardMetric(
                label: 'Average Duration',
                value: data.averageDurationLabel,
              ),
              _DashboardMetric(
                label: 'Last Run',
                value: data.lastRun?.resultBadge ?? '—',
              ),
              _DashboardMetric(
                label: 'Recent Failures',
                value: '${data.recentFailures.length}',
              ),
            ],
          ),
          if (data.recentRuns.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Recent Runs', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            ...data.recentRuns
                .take(5)
                .map(
                  (run) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            run.suite.isEmpty ? run.projectName : run.suite,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: run.resultBadge,
                          filled: run.resultBadge == 'PASS',
                          dotColor: switch (run.resultBadge) {
                            'PASS' => context.palette.success,
                            'FAIL' || 'ERROR' => context.palette.error,
                            'NO TESTS' ||
                            'CANCELLED' ||
                            'ABORTED' => context.palette.warning,
                            _ => context.palette.textMuted,
                          },
                        ),
                        if (run.durationLabel != '—') ...[
                          const SizedBox(width: 8),
                          Text(
                            run.durationLabel,
                            style: TextStyle(
                              color: context.palette.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
          if (data.recentFailures.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Recent Failures',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            ...data.recentFailures
                .take(3)
                .map(
                  (run) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            run.suite.isEmpty ? run.projectName : run.suite,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: run.resultBadge,
                          filled: false,
                          dotColor: context.palette.error,
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
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

class _RecentRunsBody extends StatelessWidget {
  const _RecentRunsBody({
    required this.runs,
    this.runningStatus,
    this.lastRunLabel,
  });

  final List<ExecutionInfo> runs;
  final ExecutionStatus? runningStatus;
  final String? lastRunLabel;

  @override
  Widget build(BuildContext context) {
    if (runningStatus != null) {
      return Row(
        children: [
          StatusBadge(
            label: runningStatus!.label,
            filled: true,
            dotColor: context.palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              lastRunLabel ?? 'Execution in progress',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    if (runs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No executions yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: runs.take(3).map((run) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  run.suite.isEmpty ? run.projectName : run.suite,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: run.status.label,
                filled: run.status == ExecutionStatus.finished,
                dotColor: _statusColor(context.palette, run.status),
              ),
              if (run.durationLabel != '—') ...[
                const SizedBox(width: 8),
                Text(
                  run.durationLabel,
                  style: TextStyle(
                    color: context.palette.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _statusColor(AppPalette palette, ExecutionStatus status) {
    return switch (status) {
      ExecutionStatus.finished => palette.success,
      ExecutionStatus.failed => palette.error,
      ExecutionStatus.cancelled => palette.warning,
      ExecutionStatus.aborted => palette.warning,
      ExecutionStatus.running ||
      ExecutionStatus.starting ||
      ExecutionStatus.stopping => palette.accent,
      ExecutionStatus.idle => palette.textMuted,
    };
  }
}

class _RecentProjectsBody extends StatelessWidget {
  const _RecentProjectsBody({
    required this.projects,
    required this.isLoading,
    required this.onOpen,
  });

  final List<ProjectInfo> projects;
  final bool isLoading;
  final ValueChanged<ProjectInfo> onOpen;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No recent projects yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: projects.take(6).map((project) {
        return ExplorerTreeItem(
          icon: Icons.folder_outlined,
          label: project.name,
          tooltip: '${project.name}\n${project.path}',
          onTap: () => onOpen(project),
        );
      }).toList(),
    );
  }
}

class _RecentFilesBody extends StatelessWidget {
  const _RecentFilesBody({required this.paths, this.onOpen});

  final List<String> paths;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No recent files yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: paths.take(10).map((path) {
        final parts = path.replaceAll('\\', '/').split('/');
        final name = parts.isEmpty ? path : parts.last;
        return ExplorerTreeItem(
          icon: Icons.description_outlined,
          label: name,
          tooltip: path,
          onTap: onOpen == null ? null : () => onOpen!(path),
          trailing: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.palette.textMuted, fontSize: 10),
          ),
        );
      }).toList(),
    );
  }
}

class _OpenEditorsBody extends StatelessWidget {
  const _OpenEditorsBody({required this.paths, this.onOpen});

  final List<String> paths;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No open editors.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: paths.map((path) {
        final parts = path.replaceAll('\\', '/').split('/');
        final name = parts.isEmpty ? path : parts.last;
        return ExplorerTreeItem(
          icon: Icons.edit_outlined,
          label: name,
          tooltip: path,
          onTap: onOpen == null ? null : () => onOpen!(path),
        );
      }).toList(),
    );
  }
}

class _RecentWorkspacesBody extends StatelessWidget {
  const _RecentWorkspacesBody({
    required this.workspaces,
    required this.isLoading,
    required this.onOpen,
  });

  final List<WorkspaceInfo> workspaces;
  final bool isLoading;
  final ValueChanged<WorkspaceInfo> onOpen;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (workspaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No recent workspaces.\nCreate or open a workspace to get started.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: workspaces.take(6).map((workspace) {
        return ExplorerTreeItem(
          icon: Icons.work_outline,
          label: workspace.name,
          tooltip: '${workspace.name}\n${workspace.path}',
          onTap: () => onOpen(workspace),
        );
      }).toList(),
    );
  }
}
