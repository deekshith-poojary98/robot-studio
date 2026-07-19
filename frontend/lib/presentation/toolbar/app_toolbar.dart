import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import '../widgets/toolbar_button.dart';

class AppToolbar extends StatelessWidget {
  const AppToolbar({
    super.key,
    required this.panelTitle,
    required this.workspaceLabel,
    required this.environmentLabel,
    required this.backendConnected,
    required this.backendVersion,
    this.environmentNames = const [],
    this.selectedEnvironmentName,
    this.onEnvironmentSelected,
    this.onManageEnvironments,
    this.robotFrameworkInstalled = false,
    this.robotFrameworkVersion,
    this.onInstallRobotFramework,
    this.onOpenPackageManager,
    this.onRun,
    this.onRunProject,
    this.onStop,
    this.executionStatusLabel,
    this.executionElapsedLabel,
    this.isExecutionRunning = false,
    this.onNewWorkspace,
    this.onOpenWorkspace,
  });

  final String panelTitle;
  final String workspaceLabel;
  final String environmentLabel;
  final bool backendConnected;
  final String? backendVersion;
  final List<String> environmentNames;
  final String? selectedEnvironmentName;
  final ValueChanged<String>? onEnvironmentSelected;
  final VoidCallback? onManageEnvironments;
  final bool robotFrameworkInstalled;
  final String? robotFrameworkVersion;
  final VoidCallback? onInstallRobotFramework;
  final VoidCallback? onOpenPackageManager;
  final VoidCallback? onRun;
  final VoidCallback? onRunProject;
  final VoidCallback? onStop;
  final String? executionStatusLabel;
  final String? executionElapsedLabel;
  final bool isExecutionRunning;
  final VoidCallback? onNewWorkspace;
  final VoidCallback? onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            panelTitle.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 8),
          Text(
            backendVersion != null ? 'v$backendVersion' : 'offline',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(width: 14),
          _SelectorChip(
            icon: Icons.folder_outlined,
            label: workspaceLabel,
            onTap: onOpenWorkspace,
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
          const SizedBox(width: 8),
          _RobotFrameworkBadge(
            installed: robotFrameworkInstalled,
            version: robotFrameworkVersion,
            enabled: backendConnected && selectedEnvironmentName != null,
            onInstall: onInstallRobotFramework,
            onOpenPackages: onOpenPackageManager,
          ),
          const SizedBox(width: 14),
          ToolbarButton(
            icon: Icons.play_arrow_rounded,
            label: 'Run',
            primary: true,
            showLabel: true,
            onTap: isExecutionRunning ? null : onRun,
          ),
          const SizedBox(width: 6),
          ToolbarButton(
            icon: Icons.playlist_play_rounded,
            label: 'Run Project',
            showLabel: true,
            onTap: isExecutionRunning ? null : onRunProject,
          ),
          const SizedBox(width: 6),
          ToolbarButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            showLabel: true,
            danger: true,
            onTap: isExecutionRunning ? onStop : null,
          ),
          if (executionStatusLabel != null) ...[
            const SizedBox(width: 10),
            StatusBadge(
              label: isExecutionRunning
                  ? '${executionStatusLabel!} · ${executionElapsedLabel ?? '0s'}'
                  : executionStatusLabel!,
              filled: isExecutionRunning,
              dotColor: isExecutionRunning ? AppColors.accent : AppColors.textMuted,
            ),
          ],
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, size: 14, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search keywords, files, commands...',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '⌘K',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ToolbarButton(
            icon: Icons.notifications_none_outlined,
            label: 'Notifications',
            onTap: () {},
          ),
          ToolbarButton(
            icon: Icons.auto_awesome_outlined,
            label: 'AI',
            onTap: () {},
          ),
          ToolbarButton(
            icon: Icons.person_outline,
            label: 'Profile',
            onTap: () {},
          ),
        ],
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
      return EnvironmentBadge(
        label: label,
        active: false,
      );
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

class _RobotFrameworkBadge extends StatelessWidget {
  const _RobotFrameworkBadge({
    required this.installed,
    required this.version,
    required this.enabled,
    required this.onInstall,
    required this.onOpenPackages,
  });

  final bool installed;
  final String? version;
  final bool enabled;
  final VoidCallback? onInstall;
  final VoidCallback? onOpenPackages;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const EnvironmentBadge(
        label: 'Robot —',
        active: false,
      );
    }

    if (installed) {
      return InkWell(
        onTap: onOpenPackages,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: EnvironmentBadge(
          label: version == null
              ? '✓ Robot Framework'
              : '✓ Robot $version',
          active: true,
        ),
      );
    }

    return InkWell(
      onTap: onInstall ?? onOpenPackages,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: const StatusBadge(
        label: '⚠ Robot Framework Missing',
        dotColor: AppColors.warning,
      ),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
  }
}
