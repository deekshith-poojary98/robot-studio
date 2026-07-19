import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../../core/theme/app_theme.dart';
import '../sidebar/sidebar_panel.dart';
import '../widgets/explorer_tree.dart';
import '../widgets/panel_header.dart';
import '../workspace/workspace_explorer.dart';

class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.panel,
    this.workspace,
    this.projects = const [],
    this.isLoadingProjects = false,
    this.selectedProject,
    this.onSelectProject,
    this.onNewProject,
    this.onImportProject,
    this.environments = const [],
    this.isLoadingEnvironments = false,
    this.selectedEnvironment,
    this.onSelectEnvironment,
    this.onManageEnvironments,
    this.onOpenPackageManager,
    this.recentRuns = const [],
    this.onSelectReport,
    this.onOpenReports,
    this.backendVersion,
  });

  final SidebarPanel panel;
  final WorkspaceInfo? workspace;
  final List<ProjectInfo> projects;
  final bool isLoadingProjects;
  final ProjectInfo? selectedProject;
  final ValueChanged<ProjectInfo>? onSelectProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onImportProject;
  final List<EnvironmentInfo> environments;
  final bool isLoadingEnvironments;
  final EnvironmentInfo? selectedEnvironment;
  final ValueChanged<EnvironmentInfo>? onSelectEnvironment;
  final VoidCallback? onManageEnvironments;
  final VoidCallback? onOpenPackageManager;
  final List<ExecutionInfo> recentRuns;
  final ValueChanged<ExecutionInfo>? onSelectReport;
  final VoidCallback? onOpenReports;
  final String? backendVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: panel.label,
            trailing: Text(
              backendVersion != null ? 'v$backendVersion' : '',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (panel == SidebarPanel.explorer) {
      if (workspace == null) {
        return _EmptyToolView(
          icon: panel.icon,
          message: 'Open a workspace to browse projects and files.',
        );
      }
      return WorkspaceExplorer(
        workspace: workspace!,
        projects: projects,
        isLoadingProjects: isLoadingProjects,
        selectedProject: selectedProject,
        onSelectProject: onSelectProject ?? (_) {},
        onNewProject: onNewProject ?? () {},
        onImportProject: onImportProject ?? () {},
        environments: environments,
        isLoadingEnvironments: isLoadingEnvironments,
        selectedEnvironment: selectedEnvironment,
        onSelectEnvironment: onSelectEnvironment,
        onManageEnvironments: onManageEnvironments,
        onOpenPackageManager: onOpenPackageManager,
        recentRuns: recentRuns,
        onSelectReport: onSelectReport,
        onOpenReports: onOpenReports,
      );
    }

    if (panel == SidebarPanel.packages) {
      return _EmptyToolView(
        icon: panel.icon,
        message: workspace == null
            ? 'Open a workspace to manage packages.'
            : 'Package Manager is open in the main view.',
      );
    }

    if (panel == SidebarPanel.search || panel == SidebarPanel.keywords) {
      return _EmptyToolView(
        icon: panel.icon,
        message: workspace == null
            ? 'Open a workspace to search symbols.'
            : panel == SidebarPanel.keywords
                ? 'Keyword search is open in the main view.'
                : 'Search is open in the main view.',
      );
    }

    return _PlaceholderTree(panel: panel);
  }
}

class _PlaceholderTree extends StatelessWidget {
  const _PlaceholderTree({required this.panel});

  final SidebarPanel panel;

  @override
  Widget build(BuildContext context) {
    final sections = switch (panel) {
      SidebarPanel.tests => const [
          ('Test Suites', ['No suites indexed yet']),
          ('Recent Runs', ['No runs yet']),
          ('Favorites', ['None']),
        ],
      SidebarPanel.keywords => const [
          ('Libraries', ['Open a workspace to discover keywords']),
          ('User Keywords', ['None']),
          ('Global Keywords', ['None']),
        ],
      SidebarPanel.search => const [],
      SidebarPanel.packages => const [
          ('Installed', ['Open Package Manager to view packages']),
          ('Updates Available', ['None']),
          ('Search Packages', ['Browse PyPI...']),
        ],
      SidebarPanel.reports => const [
          ('Recent', ['No reports yet']),
        ],
      SidebarPanel.ai => const [
          ('Threads', [
            'Explain last failure',
            'Generate login keyword',
            'Refactor smoke suite',
          ]),
        ],
      SidebarPanel.explorer => const [],
    };

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final section in sections)
          ToolSection(
            title: section.$1,
            children: [
              for (final item in section.$2)
                ExplorerTreeItem(
                  icon: Icons.folder_outlined,
                  label: item,
                  indent: 1,
                ),
            ],
          ),
      ],
    );
  }
}

class _EmptyToolView extends StatelessWidget {
  const _EmptyToolView({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
