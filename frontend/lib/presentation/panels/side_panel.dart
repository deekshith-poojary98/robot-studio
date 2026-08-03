import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/test_explorer_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../../core/theme/app_theme.dart';
import '../search/find_in_files_panel.dart';
import '../sidebar/sidebar_panel.dart';
import '../tests/test_explorer_panel.dart';
import '../widgets/empty_state.dart';
import '../widgets/explorer_tree.dart';
import '../widgets/panel_header.dart';
import '../widgets/virtual_file_tree.dart';
import '../workspace/workspace_explorer.dart';
import '../../core/gateway/models/content_search_info.dart';

class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.panel,
    this.width = defaultWidth,
    this.workspace,
    this.projects = const [],
    this.isLoadingProjects = false,
    this.selectedProject,
    this.onSelectProject,
    this.onNewProject,
    this.onImportProject,
    this.recentRuns = const [],
    this.onSelectReport,
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
    this.onExpandTestNode,
    this.currentEditorPath,
    this.onOpenProject,
    this.onRunProject,
    this.fileRows = const [],
    this.isLoadingFileTree = false,
    this.onOpenFile,
    this.onToggleDirectory,
    this.gitFileStatuses = const {},
    this.fileTreeKey,
    this.onEnsureExpanded,
    this.onCreateEntry,
    this.onRenameEntry,
    this.onDeleteEntry,
    this.onDuplicateEntry,
    this.onMoveEntry,
    this.onCopyRelativePath,
    this.onCopyAbsolutePath,
    this.onRevealInOs,
    this.onCollapseAllFolders,
    this.outline = const [],
    this.isLoadingOutline = false,
    this.selectedOutlineId,
    this.onOutlineSelect,
    this.onContentSearch,
    this.onOpenContentMatch,
    this.onOpenSymbols,
  });

  final SidebarPanel panel;
  final double width;
  final WorkspaceInfo? workspace;
  final List<ProjectInfo> projects;
  final bool isLoadingProjects;
  final ProjectInfo? selectedProject;
  final ValueChanged<ProjectInfo>? onSelectProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onImportProject;
  final List<ExecutionInfo> recentRuns;
  final ValueChanged<ExecutionInfo>? onSelectReport;
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
  final Future<void> Function(TestNodeInfo node)? onExpandTestNode;
  final String? currentEditorPath;
  final VoidCallback? onOpenProject;
  final VoidCallback? onRunProject;
  final List<FlatFileTreeRow> fileRows;
  final bool isLoadingFileTree;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String>? onToggleDirectory;
  final Map<String, GitFileStatus> gitFileStatuses;
  final GlobalKey<VirtualFileTreeState>? fileTreeKey;
  final Future<void> Function(String path)? onEnsureExpanded;
  final Future<void> Function({
    required String parentPath,
    required String name,
    required bool isDirectory,
  })?
  onCreateEntry;
  final Future<void> Function({required String path, required String newName})?
  onRenameEntry;
  final Future<void> Function(List<String> paths)? onDeleteEntry;
  final Future<void> Function(String path)? onDuplicateEntry;
  final Future<void> Function({
    required List<String> sourcePaths,
    required String destinationParentPath,
  })?
  onMoveEntry;
  final ValueChanged<List<String>>? onCopyRelativePath;
  final ValueChanged<List<String>>? onCopyAbsolutePath;
  final ValueChanged<String>? onRevealInOs;
  final VoidCallback? onCollapseAllFolders;
  final List<IndexedSymbolInfo> outline;
  final bool isLoadingOutline;
  final String? selectedOutlineId;
  final ValueChanged<IndexedSymbolInfo>? onOutlineSelect;
  final Future<ContentSearchResultInfo> Function(String query)? onContentSearch;
  final void Function(String path, int line, int column)? onOpenContentMatch;
  final VoidCallback? onOpenSymbols;

  /// Default / min / max widths for the resizable side content column.
  static const double defaultWidth = 280;
  static const double minWidth = 200;
  static const double maxWidth = 480;

  /// Panels that own the side rail. Everything else lives in the main view, so
  /// showing a side column that says "open in the main view" is dead chrome.
  static bool hasSideContent(SidebarPanel panel) {
    return panel == SidebarPanel.explorer ||
        panel == SidebarPanel.tests ||
        panel == SidebarPanel.reports ||
        panel == SidebarPanel.search;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasSideContent(panel)) return const SizedBox.shrink();
    return SizedBox(
      width: width.clamp(minWidth, maxWidth),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelHeader(
              title: panel == SidebarPanel.search ? 'Find in Files' : panel.label,
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
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
        fileRows: fileRows,
        isLoadingFileTree: isLoadingFileTree,
        selectedFilePath: currentEditorPath,
        onOpenFile: onOpenFile,
        onToggleDirectory: onToggleDirectory,
        gitFileStatuses: gitFileStatuses,
        fileTreeKey: fileTreeKey,
        onEnsureExpanded: onEnsureExpanded,
        onCreateEntry: onCreateEntry,
        onRenameEntry: onRenameEntry,
        onDeleteEntry: onDeleteEntry,
        onDuplicateEntry: onDuplicateEntry,
        onMoveEntry: onMoveEntry,
        onCopyRelativePath: onCopyRelativePath,
        onCopyAbsolutePath: onCopyAbsolutePath,
        onRevealInOs: onRevealInOs,
        onCollapseAllFolders: onCollapseAllFolders,
        outline: outline,
        isLoadingOutline: isLoadingOutline,
        selectedOutlineId: selectedOutlineId,
        onOutlineSelect: onOutlineSelect,
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
            title: 'Runs',
            children: [
              for (final run in recentRuns)
                ExplorerTreeItem(
                  icon: Icons.assessment_outlined,
                  label: run.sidebarLabel,
                  semanticLabel:
                      '${run.runNumberLabel}, ${run.resultBadge}, ${run.suite.isEmpty ? run.projectName : run.suite}',
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
        onExpandNode: onExpandTestNode,
        currentFilePath: currentEditorPath,
      );
    }

    if (panel == SidebarPanel.search) {
      return FindInFilesPanel(
        hasProject: workspace != null,
        onSearch: onContentSearch ??
            ((_) async => const ContentSearchResultInfo(
                  query: '',
                  truncated: false,
                  filesScanned: 0,
                  files: [],
                )),
        onOpenMatch: onOpenContentMatch ?? (path, line, column) {},
        onOpenSymbols: onOpenSymbols,
      );
    }

    return const SizedBox.shrink();
  }
}
