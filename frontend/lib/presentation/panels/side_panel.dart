import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/index_info.dart';
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
    this.testSuites = const [],
    this.onSelectTestSuite,
    this.fileTree = const [],
    this.onOpenFile,
    this.gitFileStatuses = const {},
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
  final List<IndexedSymbolInfo> testSuites;
  final ValueChanged<IndexedSymbolInfo>? onSelectTestSuite;
  final List<FileTreeNode> fileTree;
  final ValueChanged<String>? onOpenFile;
  final Map<String, GitFileStatus> gitFileStatuses;

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
        fileTree: fileTree,
        onOpenFile: onOpenFile,
        gitFileStatuses: gitFileStatuses,
      );
    }

    if (panel == SidebarPanel.sourceControl) {
      return _EmptyToolView(
        icon: panel.icon,
        message: workspace == null
            ? 'Open a workspace to use source control.'
            : 'Source Control is open in the main view.',
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

    if (panel == SidebarPanel.reports) {
      if (workspace == null) {
        return _EmptyToolView(
          icon: panel.icon,
          message: 'Open a workspace to view reports.',
        );
      }
      if (recentRuns.isEmpty) {
        return _EmptyToolView(
          icon: panel.icon,
          message: 'No reports yet. Run a suite to generate artifacts.',
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ToolSection(
            title: 'Recent',
            children: [
              for (final run in recentRuns)
                ExplorerTreeItem(
                  icon: Icons.assessment_outlined,
                  label: '${run.projectName.isEmpty ? run.suite : run.projectName} · ${run.status.passFailLabel}',
                  indent: 1,
                  onTap: onSelectReport == null ? null : () => onSelectReport!(run),
                ),
            ],
          ),
          if (onOpenReports != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextButton(
                onPressed: onOpenReports,
                child: const Text('Open Reports'),
              ),
            ),
        ],
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

    if (panel == SidebarPanel.tests) {
      if (workspace == null) {
        return _EmptyToolView(
          icon: panel.icon,
          message: 'Open a workspace to browse test suites.',
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ToolSection(
            title: 'Test Suites',
            children: [
              if (testSuites.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                  child: Text(
                    'No suites indexed yet. Rebuild the index or add .robot files.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                for (final suite in testSuites)
                  ExplorerTreeItem(
                    icon: Icons.description_outlined,
                    label: suite.name,
                    indent: 1,
                    onTap: onSelectTestSuite == null
                        ? null
                        : () => onSelectTestSuite!(suite),
                  ),
            ],
          ),
          ToolSection(
            title: 'Recent Runs',
            children: [
              if (recentRuns.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                  child: Text(
                    'No runs yet',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                for (final run in recentRuns.take(8))
                  ExplorerTreeItem(
                    icon: Icons.play_circle_outline,
                    label:
                        '${run.projectName.isEmpty ? run.suite : run.projectName} · ${run.status.passFailLabel}',
                    indent: 1,
                    onTap: onSelectReport == null
                        ? null
                        : () => onSelectReport!(run),
                  ),
            ],
          ),
        ],
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
      SidebarPanel.tests => const [],
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
      SidebarPanel.plugins => const [
          ('Workspace Plugins', ['Workspace/Plugins']),
          ('User Plugins', ['~/.robotstudio/plugins']),
          ('Built-in', ['Core capabilities']),
        ],
      SidebarPanel.sourceControl => const [
          ('Changes', ['Open Source Control in the main view']),
        ],
      SidebarPanel.reports => const [],
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
