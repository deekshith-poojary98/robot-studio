import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../../core/theme/app_theme.dart';
import '../project/project_details_panel.dart';
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
    required this.onOpenRecentWorkspace,
    required this.onOpenRecentProject,
    this.onNewProject,
    this.onImportProject,
    this.onManageEnvironments,
    this.activeEnvironmentLabel,
    this.recentRuns = const [],
    this.runningStatus,
    this.lastRunLabel,
  });

  final List<WorkspaceInfo> recentWorkspaces;
  final List<ProjectInfo> recentProjects;
  final bool isLoadingRecent;
  final VoidCallback onNewWorkspace;
  final VoidCallback onOpenWorkspace;
  final ValueChanged<WorkspaceInfo> onOpenRecentWorkspace;
  final ValueChanged<ProjectInfo> onOpenRecentProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onImportProject;
  final VoidCallback? onManageEnvironments;
  final String? activeEnvironmentLabel;
  final List<ExecutionInfo> recentRuns;
  final ExecutionStatus? runningStatus;
  final String? lastRunLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Robot Studio',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'High-performance workspace for Robot Framework development.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 780;
                final tiles = [
                  QuickActionTile(
                    icon: Icons.add,
                    label: 'New Workspace',
                    subtitle: 'Create a Robot Studio workspace',
                    onTap: onNewWorkspace,
                  ),
                  QuickActionTile(
                    icon: Icons.folder_open_outlined,
                    label: 'Open Workspace',
                    subtitle: 'Open an existing workspace',
                    onTap: onOpenWorkspace,
                  ),
                  QuickActionTile(
                    icon: Icons.note_add_outlined,
                    label: 'Create Robot Project',
                    subtitle: 'Requires an open workspace',
                    onTap: onNewProject ?? () {},
                  ),
                  QuickActionTile(
                    icon: Icons.memory_outlined,
                    label: 'Manage Environments',
                    subtitle: 'Create and activate Python environments',
                    onTap: onManageEnvironments ?? () {},
                  ),
                ];

                if (wide) {
                  return Row(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: tiles[i]),
                      ],
                    ],
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      tiles[i],
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth > 860;
                final projects = InfoCard(
                  title: 'Recent Projects',
                  child: _RecentProjectsBody(
                    projects: recentProjects,
                    isLoading: isLoadingRecent,
                    onOpen: onOpenRecentProject,
                  ),
                );
                final workspaces = InfoCard(
                  title: 'Recent Workspaces',
                  child: _RecentWorkspacesBody(
                    workspaces: recentWorkspaces,
                    isLoading: isLoadingRecent,
                    onOpen: onOpenRecentWorkspace,
                  ),
                );

                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: projects),
                      const SizedBox(width: 12),
                      Expanded(child: workspaces),
                    ],
                  );
                }

                return Column(
                  children: [
                    projects,
                    const SizedBox(height: 12),
                    workspaces,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (recentRuns.isNotEmpty || runningStatus != null)
              InfoCard(
                title: 'Recent Runs',
                child: _RecentRunsBody(
                  runs: recentRuns,
                  runningStatus: runningStatus,
                  lastRunLabel: lastRunLabel,
                ),
              ),
            if (recentRuns.isNotEmpty || runningStatus != null)
              const SizedBox(height: 12),
            InfoCard(
              title: 'Active Environment',
              child: Row(
                children: [
                  EnvironmentBadge(
                    label: activeEnvironmentLabel ?? 'No environment',
                    active: activeEnvironmentLabel != null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      activeEnvironmentLabel == null
                          ? 'Open a workspace and create a Python environment.'
                          : 'Used for execution, packages, and language services.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            dotColor: AppColors.accent,
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
                dotColor: _statusColor(run.status),
              ),
              if (run.durationLabel != '—') ...[
                const SizedBox(width: 8),
                Text(
                  run.durationLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
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

  Color _statusColor(ExecutionStatus status) {
    return switch (status) {
      ExecutionStatus.finished => AppColors.success,
      ExecutionStatus.failed => AppColors.error,
      ExecutionStatus.cancelled => AppColors.warning,
      ExecutionStatus.running ||
      ExecutionStatus.starting ||
      ExecutionStatus.stopping =>
        AppColors.accent,
      ExecutionStatus.idle => AppColors.textMuted,
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
          icon: iconForProjectType(project.type),
          label: project.name,
          onTap: () => onOpen(project),
          trailing: Text(
            project.type.label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
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
          onTap: () => onOpen(workspace),
        );
      }).toList(),
    );
  }
}
