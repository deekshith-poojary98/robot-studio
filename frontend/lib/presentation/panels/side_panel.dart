import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/test_explorer_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../../core/theme/app_theme.dart';
import '../sidebar/sidebar_panel.dart';
import '../tests/test_explorer_panel.dart';
import '../widgets/empty_state.dart';
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
    this.testTree,
    this.isLoadingTestTree = false,
    this.testFilter = '',
    this.onTestFilterChanged,
    this.onRefreshTests,
    this.onRunAllTests,
    this.onRunCurrentFileTests,
    this.onRunFailedTests,
    this.onRunTestNode,
    this.onOpenTestNode,
    this.onRevealTestNode,
    this.currentEditorPath,
    this.onOpenProject,
    this.onRunProject,
    this.fileRows = const [],
    this.isLoadingFileTree = false,
    this.onOpenFile,
    this.onToggleDirectory,
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
  final TestNodeInfo? testTree;
  final bool isLoadingTestTree;
  final String testFilter;
  final ValueChanged<String>? onTestFilterChanged;
  final VoidCallback? onRefreshTests;
  final VoidCallback? onRunAllTests;
  final VoidCallback? onRunCurrentFileTests;
  final VoidCallback? onRunFailedTests;
  final ValueChanged<TestNodeInfo>? onRunTestNode;
  final ValueChanged<TestNodeInfo>? onOpenTestNode;
  final ValueChanged<TestNodeInfo>? onRevealTestNode;
  final String? currentEditorPath;
  final VoidCallback? onOpenProject;
  final VoidCallback? onRunProject;
  final List<FlatFileTreeRow> fileRows;
  final bool isLoadingFileTree;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String>? onToggleDirectory;
  final Map<String, GitFileStatus> gitFileStatuses;

  /// Panels that own the side rail. Everything else lives in the main view, so
  /// showing a 280px column that says "open in the main view" is dead chrome.
  static bool hasSideContent(SidebarPanel panel) {
    return panel == SidebarPanel.explorer ||
        panel == SidebarPanel.tests ||
        panel == SidebarPanel.reports;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasSideContent(panel)) return const SizedBox.shrink();
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: panel.label),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (panel == SidebarPanel.explorer) {
      if (workspace == null) {
        return EmptyState(
          icon: panel.icon,
          title: 'No project open',
          message: 'Open a Robot Framework project folder to browse its files.',
          actionLabel: onOpenProject == null ? null : 'Open Project…',
          onAction: onOpenProject,
          compact: true,
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
        fileRows: fileRows,
        isLoadingFileTree: isLoadingFileTree,
        onOpenFile: onOpenFile,
        onToggleDirectory: onToggleDirectory,
        gitFileStatuses: gitFileStatuses,
      );
    }

    if (panel == SidebarPanel.reports) {
      if (workspace == null) {
        return EmptyState(
          icon: panel.icon,
          title: 'No project open',
          message: 'Open a project to see its run history and reports.',
          actionLabel: onOpenProject == null ? null : 'Open Project…',
          onAction: onOpenProject,
          compact: true,
        );
      }
      if (recentRuns.isEmpty) {
        return EmptyState(
          icon: panel.icon,
          title: 'No reports yet',
          message: 'Run your first Robot Framework suite to generate a report.',
          actionLabel: onRunProject == null ? null : 'Run Suite',
          onAction: onRunProject,
          compact: true,
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

    if (panel == SidebarPanel.tests) {
      if (workspace == null) {
        return EmptyState(
          icon: panel.icon,
          title: 'No project open',
          message: 'Open a project to browse its suites, tests, and tags.',
          actionLabel: onOpenProject == null ? null : 'Open Project…',
          onAction: onOpenProject,
          compact: true,
        );
      }
      return TestExplorerPanel(
        tree: testTree,
        isLoading: isLoadingTestTree,
        filter: testFilter,
        onFilterChanged: onTestFilterChanged,
        onRefresh: onRefreshTests,
        onRunAll: onRunAllTests,
        onRunCurrentFile: onRunCurrentFileTests,
        onRunFailed: onRunFailedTests,
        onRunNode: onRunTestNode,
        onOpenFile: onOpenTestNode,
        onRevealInExplorer: onRevealTestNode,
        currentFilePath: currentEditorPath,
      );
    }

    return const SizedBox.shrink();
  }
}
