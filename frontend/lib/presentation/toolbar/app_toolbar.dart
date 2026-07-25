import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../git/branch_selector.dart';
import '../widgets/status_badge.dart';
import '../widgets/toolbar_button.dart';

class AppToolbar extends StatelessWidget {
  const AppToolbar({
    super.key,
    required this.projectLabel,
    required this.environmentLabel,
    required this.backendConnected,
    this.environmentNames = const [],
    this.selectedEnvironmentName,
    this.onEnvironmentSelected,
    this.onManageEnvironments,
    this.onRun,
    this.onRunProject,
    this.onStop,
    this.executionStatusLabel,
    this.executionElapsedLabel,
    this.isExecutionRunning = false,
    this.onExecutionStatusTap,
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
  });

  final String projectLabel;
  final String environmentLabel;
  final bool backendConnected;
  final List<String> environmentNames;
  final String? selectedEnvironmentName;
  final ValueChanged<String>? onEnvironmentSelected;
  final VoidCallback? onManageEnvironments;
  final VoidCallback? onRun;
  final VoidCallback? onRunProject;
  final VoidCallback? onStop;
  final String? executionStatusLabel;
  final String? executionElapsedLabel;
  final bool isExecutionRunning;
  final VoidCallback? onExecutionStatusTap;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
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
                    _SelectorChip(
                      icon: Icons.folder_outlined,
                      label: projectLabel,
                      tooltip: 'Open a project folder',
                      onTap: onOpenProject ?? onOpenWorkspace,
                    ),
                    const SizedBox(width: 8),
                    _EnvironmentSelector(
                      label: environmentLabel,
                      names: environmentNames,
                      selectedName: selectedEnvironmentName,
                      enabled: backendConnected && environmentNames.isNotEmpty,
                      onSelected: onEnvironmentSelected,
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
                            ? 'Open execution logs'
                            : 'Last run: $executionStatusLabel — open execution logs',
                        child: InkWell(
                          onTap: onExecutionStatusTap,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: StatusBadge(
                            label: isExecutionRunning
                                ? '${executionStatusLabel!} · ${executionElapsedLabel ?? '0s'}'
                                : 'Last: $executionStatusLabel',
                            filled: isExecutionRunning,
                            dotColor: isExecutionRunning
                                ? AppColors.accent
                                : executionStatusLabel == 'Failed'
                                ? AppColors.error
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    ToolbarButton(
                      key: const Key('toolbar.run'),
                      icon: Icons.play_arrow_rounded,
                      label: 'Run',
                      primary: true,
                      showLabel: true,
                      tooltip: !canRun
                          ? 'Open a project to run the current file'
                          : isExecutionRunning
                          ? 'Stop the current run first'
                          : 'Run current file',
                      onTap: isExecutionRunning || !canRun ? null : onRun,
                    ),
                    const SizedBox(width: 4),
                    ToolbarButton(
                      key: const Key('toolbar.run-project'),
                      icon: Icons.playlist_play_rounded,
                      label: 'Run Project',
                      tooltip: !canRunProject
                          ? 'Open a project to run'
                          : isExecutionRunning
                          ? 'Stop the current run first'
                          : 'Run the whole project',
                      onTap: isExecutionRunning || !canRunProject
                          ? null
                          : onRunProject,
                    ),
                    const SizedBox(width: 2),
                    ToolbarButton(
                      key: const Key('toolbar.stop'),
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      danger: isExecutionRunning,
                      tooltip: isExecutionRunning
                          ? 'Stop the current run'
                          : 'Nothing to stop',
                      onTap: isExecutionRunning ? onStop : null,
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
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'fetch',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_download_outlined, size: 16),
            title: Text('Fetch'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'pull',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_outlined, size: 16),
            title: Text('Pull'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'push',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.upload_outlined, size: 16),
            title: Text('Push'),
          ),
        ),
      ],
      child: Container(
        height: 28,
        width: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: AppColors.border),
          color: AppColors.surfaceElevated,
        ),
        child: const Icon(
          Icons.more_horiz,
          size: 15,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({this.onTap});

  final VoidCallback? onTap;

  static String get _shortcutLabel {
    if (kIsWeb) return 'Ctrl+K';
    return Platform.isMacOS ? '⌘K' : 'Ctrl+K';
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
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(Icons.search, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Search commands, files, symbols…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            Text(
              _shortcutLabel,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
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
    required this.onManage,
  });

  final String label;
  final List<String> names;
  final String? selectedName;
  final bool enabled;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return EnvironmentBadge(label: label, active: false);
    }

    return PopupMenuButton<String>(
      tooltip: 'Select environment',
      onSelected: (value) {
        if (value == '__manage__') {
          onManage?.call();
          return;
        }
        onSelected?.call(value);
      },
      itemBuilder: (context) => [
        ...names.map(
          (name) => CheckedPopupMenuItem<String>(
            value: name,
            checked: name == selectedName,
            child: Text(name),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__manage__',
          child: Text('Manage Environments…'),
        ),
      ],
      child: EnvironmentBadge(
        label: selectedName ?? label,
        active: selectedName != null,
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );

    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
