import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/run_configuration_info.dart';
import '../../core/theme/app_theme.dart';
import '../git/branch_selector.dart';
import '../run_configuration/run_configuration_selector.dart';
import '../widgets/app_menu.dart';
import '../widgets/status_badge.dart';
import '../widgets/toolbar_button.dart';
import '../workspace/explorer_file_actions.dart';

class AppToolbar extends StatelessWidget {
  const AppToolbar({
    super.key,
    required this.projectLabel,
    required this.environmentLabel,
    required this.backendConnected,
    this.environmentNames = const [],
    this.selectedEnvironmentName,
    this.environmentBroken = false,
    this.onEnvironmentSelected,
    this.onCreateEnvironment,
    this.onManageEnvironments,
    this.runConfigurations = const [],
    this.activeRunConfigurationId,
    this.onRunConfigurationSelected,
    this.onNewRunConfiguration,
    this.onManageRunConfigurations,
    this.runConfigurationsEnabled = false,
    this.onRun,
    this.onRunProject,
    this.onStop,
    this.executionStatusLabel,
    this.executionElapsedLabel,
    this.isExecutionRunning = false,
    this.onExecutionStatusTap,
    this.recentProjects = const [],
    this.selectedProjectId,
    this.onRecentProjectSelected,
    this.onRevealProject,
    this.onNewProject,
    this.onNewWorkspace,
    this.onOpenWorkspace,
    this.onOpenProject,
    this.onOpenSearch,
    this.gitBranchLabel,
    this.gitBranches = const [],
    this.onGitBranchSelected,
    this.onGitCreateBranch,
    this.onGitDeleteBranch,
    this.onGitFetch,
    this.onGitPull,
    this.onGitPush,
    this.showGitRemoteActions = false,
    this.canRun = true,
    this.canRunProject = true,
    this.robotFrameworkReady = true,
  });

  final String projectLabel;
  final String environmentLabel;
  final bool backendConnected;
  final List<String> environmentNames;
  final String? selectedEnvironmentName;
  final bool environmentBroken;
  final ValueChanged<String>? onEnvironmentSelected;
  final VoidCallback? onCreateEnvironment;
  final VoidCallback? onManageEnvironments;
  final List<RunConfigurationInfo> runConfigurations;
  final String? activeRunConfigurationId;
  final ValueChanged<String?>? onRunConfigurationSelected;
  final VoidCallback? onNewRunConfiguration;
  final VoidCallback? onManageRunConfigurations;
  final bool runConfigurationsEnabled;
  final VoidCallback? onRun;
  final VoidCallback? onRunProject;
  final VoidCallback? onStop;
  final String? executionStatusLabel;
  final String? executionElapsedLabel;
  final bool isExecutionRunning;
  final VoidCallback? onExecutionStatusTap;
  final List<ProjectInfo> recentProjects;
  final String? selectedProjectId;
  final ValueChanged<ProjectInfo>? onRecentProjectSelected;
  final VoidCallback? onRevealProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onNewWorkspace;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenProject;
  final VoidCallback? onOpenSearch;
  final String? gitBranchLabel;
  final List<String> gitBranches;
  final ValueChanged<String>? onGitBranchSelected;
  final ValueChanged<String>? onGitCreateBranch;
  final ValueChanged<String>? onGitDeleteBranch;
  final VoidCallback? onGitFetch;
  final VoidCallback? onGitPull;
  final VoidCallback? onGitPush;
  final bool showGitRemoteActions;
  final bool canRun;
  final bool canRunProject;
  final bool robotFrameworkReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.borderSubtle)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ProjectSelector(
                      label: projectLabel,
                      recentProjects: recentProjects,
                      selectedProjectId: selectedProjectId,
                      onOpenProject: onOpenProject ?? onOpenWorkspace,
                      onNewProject: onNewProject,
                      onRecentProjectSelected: onRecentProjectSelected,
                      onRevealProject: onRevealProject,
                    ),
                    const SizedBox(width: 8),
                    _EnvironmentSelector(
                      label: environmentLabel,
                      names: environmentNames,
                      selectedName: selectedEnvironmentName,
                      broken: environmentBroken,
                      enabled: backendConnected,
                      onSelected: onEnvironmentSelected,
                      onCreate: onCreateEnvironment,
                      onManage: onManageEnvironments,
                    ),
                    if (backendConnected) ...[
                      const SizedBox(width: 8),
                      BranchSelector(
                        branches: gitBranches
                            .map(
                              (name) => GitBranchInfo(
                                name: name,
                                current: name == gitBranchLabel,
                              ),
                            )
                            .toList(),
                        currentBranch: gitBranchLabel,
                        enabled:
                            gitBranches.isNotEmpty || gitBranchLabel != null,
                        onCheckout: onGitBranchSelected ?? (_) {},
                        onCreateBranch: onGitCreateBranch ?? (_) {},
                        onDeleteBranch: onGitDeleteBranch ?? (_) {},
                      ),
                      if (showGitRemoteActions) ...[
                        const SizedBox(width: 4),
                        _GitRemoteMenu(
                          onFetch: onGitFetch,
                          onPull: onGitPull,
                          onPush: onGitPush,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
            child: _SearchField(onTap: onOpenSearch),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (executionStatusLabel != null &&
                        (isExecutionRunning ||
                            executionStatusLabel != 'Idle')) ...[
                      Tooltip(
                        message: isExecutionRunning
                            ? 'Open Tests (run output)'
                            : 'Last run: $executionStatusLabel — open Tests',
                        child: InkWell(
                          onTap: onExecutionStatusTap,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: StatusBadge(
                            label: isExecutionRunning
                                ? '${executionStatusLabel!} · ${executionElapsedLabel ?? '0s'}'
                                : 'Last: $executionStatusLabel',
                            filled: isExecutionRunning,
                            dotColor: isExecutionRunning
                                ? context.palette.accent
                                : executionStatusLabel == 'Failed'
                                ? context.palette.error
                                : context.palette.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    RunConfigurationSelector(
                      configurations: runConfigurations,
                      activeId: activeRunConfigurationId,
                      enabled: runConfigurationsEnabled,
                      onSelected: onRunConfigurationSelected ?? (_) {},
                      onNew: onNewRunConfiguration ?? () {},
                      onManage: onManageRunConfigurations ?? () {},
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ToolbarButtonGroup(
                      buttons: [
                        ToolbarButton(
                          key: const Key('toolbar.run'),
                          icon: Icons.play_arrow_rounded,
                          label: 'Run',
                          primary: true,
                          showLabel: true,
                          tooltip: environmentBroken
                              ? 'Active environment is missing on disk — recreate or select another'
                              : !canRun && !robotFrameworkReady
                              ? "Robot Framework isn't installed in the selected environment.\nInstall Robot Framework…"
                              : !canRun && !canRunProject
                              ? 'Open a project to run the current file'
                              : !canRun
                              ? 'Open a .robot suite file to run'
                              : isExecutionRunning
                              ? 'Stop the current run first'
                              : 'Run current file',
                          onTap: isExecutionRunning || !canRun ? null : onRun,
                        ),
                        ToolbarButton(
                          key: const Key('toolbar.run-project'),
                          icon: Icons.playlist_play_rounded,
                          label: 'Project',
                          showLabel: true,
                          tooltip: environmentBroken
                              ? 'Active environment is missing on disk — recreate or select another'
                              : !canRunProject && !robotFrameworkReady
                              ? "Robot Framework isn't installed in the selected environment.\nInstall Robot Framework…"
                              : !canRunProject
                              ? 'Open a project to run'
                              : isExecutionRunning
                              ? 'Stop the current run first'
                              : 'Run the whole project',
                          onTap: isExecutionRunning || !canRunProject
                              ? null
                              : onRunProject,
                        ),
                        ToolbarButton(
                          key: const Key('toolbar.stop'),
                          icon: Icons.stop_rounded,
                          label: 'Stop',
                          showLabel: true,
                          danger: isExecutionRunning,
                          tooltip: isExecutionRunning
                              ? 'Stop the current run'
                              : 'Nothing to stop',
                          onTap: isExecutionRunning ? onStop : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary git actions live behind one control so the toolbar stays quiet.
class _GitRemoteMenu extends StatelessWidget {
  const _GitRemoteMenu({this.onFetch, this.onPull, this.onPush});

  final VoidCallback? onFetch;
  final VoidCallback? onPull;
  final VoidCallback? onPush;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Git remote actions',
      position: PopupMenuPosition.under,
      onSelected: (value) => switch (value) {
        'fetch' => onFetch?.call(),
        'pull' => onPull?.call(),
        'push' => onPush?.call(),
        _ => null,
      },
      itemBuilder: (context) => [
        AppPopupMenuItem.icon(
          value: 'fetch',
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
        ),
        AppPopupMenuItem.icon(
          value: 'pull',
          icon: Icons.download_outlined,
          label: 'Pull',
        ),
        AppPopupMenuItem.icon(
          value: 'push',
          icon: Icons.upload_outlined,
          label: 'Push',
        ),
      ],
      child: Container(
        height: AppControlHeight.toolbarChip,
        width: AppControlHeight.toolbarChip,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: context.palette.border),
          color: context.palette.surfaceElevated,
        ),
        child: Icon(
          Icons.more_horiz,
          size: 15,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({this.onTap});

  final VoidCallback? onTap;

  static String get _shortcutLabel {
    if (kIsWeb) return 'Ctrl+Shift+P';
    return Platform.isMacOS ? '⌘⇧P' : 'Ctrl+Shift+P';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: context.palette.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: context.palette.border),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: context.palette.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Search commands, files, symbols…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.palette.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              _shortcutLabel,
              style: TextStyle(color: context.palette.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentSelector extends StatelessWidget {
  const _EnvironmentSelector({
    required this.label,
    required this.names,
    required this.selectedName,
    required this.enabled,
    required this.onSelected,
    required this.onCreate,
    required this.onManage,
    this.broken = false,
  });

  final String label;
  final List<String> names;
  final String? selectedName;
  final bool enabled;
  final bool broken;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onCreate;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Tooltip(
        message: 'Backend unavailable — start it to manage environments',
        child: EnvironmentBadge(
          label: label,
          active: false,
          height: AppControlHeight.toolbarChip,
        ),
      );
    }

    final empty = names.isEmpty;
    final display = broken && selectedName != null
        ? '$selectedName · missing'
        : (selectedName ?? label);

    return PopupMenuButton<String>(
      key: const Key('toolbar.environment'),
      tooltip: empty
          ? 'Create or manage a Python environment'
          : broken
          ? 'Environment folder is missing — recreate or manage environments'
          : 'Select environment',
      onSelected: (value) {
        if (value == '__create__') {
          onCreate?.call();
          return;
        }
        if (value == '__manage__') {
          onManage?.call();
          return;
        }
        onSelected?.call(value);
      },
      itemBuilder: (context) {
        if (empty) {
          return const [
            AppPopupMenuItem<String>(
              value: '__create__',
              child: Text('Create Environment…'),
            ),
            AppPopupMenuItem<String>(
              value: '__manage__',
              child: Text('Manage Environments…'),
            ),
          ];
        }
        return [
          ...names.map(
            (name) => AppCheckedPopupMenuItem<String>(
              value: name,
              checked: name == selectedName,
              child: Text(name),
            ),
          ),
          const AppPopupMenuDivider(),
          const AppPopupMenuItem<String>(
            value: '__create__',
            child: Text('Create Environment…'),
          ),
          const AppPopupMenuItem<String>(
            value: '__manage__',
            child: Text('Manage Environments…'),
          ),
        ];
      },
      child: EnvironmentBadge(
        label: display,
        active: selectedName != null,
        broken: broken,
        height: AppControlHeight.toolbarChip,
      ),
    );
  }
}

class _ProjectSelector extends StatelessWidget {
  const _ProjectSelector({
    required this.label,
    required this.recentProjects,
    this.selectedProjectId,
    this.onOpenProject,
    this.onNewProject,
    this.onRecentProjectSelected,
    this.onRevealProject,
  });

  final String label;
  final List<ProjectInfo> recentProjects;
  final String? selectedProjectId;
  final VoidCallback? onOpenProject;
  final VoidCallback? onNewProject;
  final ValueChanged<ProjectInfo>? onRecentProjectSelected;
  final VoidCallback? onRevealProject;

  static const _open = '__open__';
  static const _new = '__new__';
  static const _reveal = '__reveal__';

  @override
  Widget build(BuildContext context) {
    final revealLabel = ExplorerFileActions.revealLabel();
    final hasProject = selectedProjectId != null;
    final tooltip = hasProject
        ? 'Switch project or $revealLabel'
        : 'Open a project folder';

    return PopupMenuButton<String>(
      key: const Key('toolbar.project'),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == _open) {
          onOpenProject?.call();
          return;
        }
        if (value == _new) {
          onNewProject?.call();
          return;
        }
        if (value == _reveal) {
          onRevealProject?.call();
          return;
        }
        for (final project in recentProjects) {
          if (project.id == value) {
            onRecentProjectSelected?.call(project);
            return;
          }
        }
      },
      itemBuilder: (context) {
        return [
          if (recentProjects.isNotEmpty) ...[
            ...recentProjects.map(
              (project) => AppCheckedPopupMenuItem<String>(
                value: project.id,
                checked: project.id == selectedProjectId,
                child: Text(project.name),
              ),
            ),
            const AppPopupMenuDivider(),
          ],
          AppPopupMenuItem<String>(
            value: _open,
            enabled: onOpenProject != null,
            child: const Text('Open Project…'),
          ),
          AppPopupMenuItem<String>(
            value: _reveal,
            enabled: hasProject && onRevealProject != null,
            child: Text(revealLabel),
          ),
          if (onNewProject != null)
            const AppPopupMenuItem<String>(
              value: _new,
              child: Text('New Project…'),
            ),
        ];
      },
      child: _SelectorChip(icon: Icons.folder_outlined, label: label),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppControlHeight.toolbarChip,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.palette.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: context.palette.textMuted,
          ),
        ],
      ),
    );
  }
}
