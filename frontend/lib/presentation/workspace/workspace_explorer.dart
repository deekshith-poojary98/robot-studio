import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../widgets/explorer_tree.dart';
import '../widgets/virtual_file_tree.dart';

class WorkspaceExplorer extends StatelessWidget {
  const WorkspaceExplorer({
    super.key,
    required this.workspace,
    required this.projects,
    required this.isLoadingProjects,
    required this.selectedProject,
    required this.onSelectProject,
    required this.onNewProject,
    required this.onImportProject,
    this.environments = const [],
    this.isLoadingEnvironments = false,
    this.selectedEnvironment,
    this.onSelectEnvironment,
    this.onManageEnvironments,
    this.onOpenPackageManager,
    this.recentRuns = const [],
    this.onSelectReport,
    this.onOpenReports,
    this.fileRows = const [],
    this.isLoadingFileTree = false,
    this.onOpenFile,
    this.onToggleDirectory,
    this.gitFileStatuses = const {},
  });

  final WorkspaceInfo workspace;
  final List<ProjectInfo> projects;
  final bool isLoadingProjects;
  final ProjectInfo? selectedProject;
  final ValueChanged<ProjectInfo> onSelectProject;
  final VoidCallback onNewProject;
  final VoidCallback onImportProject;
  final List<EnvironmentInfo> environments;
  final bool isLoadingEnvironments;
  final EnvironmentInfo? selectedEnvironment;
  final ValueChanged<EnvironmentInfo>? onSelectEnvironment;
  final VoidCallback? onManageEnvironments;
  final VoidCallback? onOpenPackageManager;
  final List<ExecutionInfo> recentRuns;
  final ValueChanged<ExecutionInfo>? onSelectReport;
  final VoidCallback? onOpenReports;
  final List<FlatFileTreeRow> fileRows;
  final bool isLoadingFileTree;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String>? onToggleDirectory;
  final Map<String, GitFileStatus> gitFileStatuses;

  bool get _isSingleProjectRoot {
    if (projects.length != 1) return false;
    final project = projects.first;
    final projectPath = project.path.replaceAll('\\', '/');
    final workspacePath = workspace.path.replaceAll('\\', '/');
    return projectPath == workspacePath;
  }

  @override
  Widget build(BuildContext context) {
    final headerName = _isSingleProjectRoot
        ? (selectedProject?.name ?? projects.first.name)
        : (selectedProject?.name ?? workspace.name);
    final headerPath = _isSingleProjectRoot
        ? (selectedProject?.path ?? projects.first.path)
        : workspace.path;
    final sectionLabel = _isSingleProjectRoot ? 'PROJECT' : 'WORKSPACE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                headerPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Text(
                sectionLabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              if (!_isSingleProjectRoot) ...[
                IconButton(
                  tooltip: 'New Project',
                  icon: const Icon(Icons.add, size: 15),
                  onPressed: onNewProject,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Import Project',
                  icon: const Icon(Icons.file_download_outlined, size: 15),
                  onPressed: onImportProject,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
        if (!_isSingleProjectRoot)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ToolSection(
              title: 'Projects',
              children: [
                if (isLoadingProjects)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (projects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                    child: Text(
                      'No projects yet. Create or import one.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  ...projects.map(
                    (project) => ExplorerTreeItem(
                      key: ValueKey(project.id),
                      icon: Icons.folder_outlined,
                      label: project.name,
                      indent: 1,
                      selected: selectedProject?.id == project.id,
                      onTap: () => onSelectProject(project),
                    ),
                  ),
              ],
            ),
          ),
        if (onOpenFile != null && onToggleDirectory != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Text(
              'FILES',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            flex: 3,
            child: VirtualFileTree(
              rows: fileRows,
              isLoading: isLoadingFileTree,
              onOpenFile: onOpenFile!,
              onToggleDirectory: onToggleDirectory!,
              gitFileStatuses: gitFileStatuses,
              emptyMessage: 'This project has no files yet.',
            ),
          ),
        ],
        Expanded(
          flex: 2,
          child: ListView(
            key: const Key('workspace-explorer-list'),
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ToolSection(
                title: 'Environments',
                trailing: onManageEnvironments == null
                    ? null
                    : IconButton(
                        tooltip: 'Manage Environments',
                        icon: const Icon(Icons.settings_outlined, size: 14),
                        onPressed: onManageEnvironments,
                        visualDensity: VisualDensity.compact,
                      ),
                children: [
                  if (isLoadingEnvironments)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (environments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                      child: Text(
                        'No environment yet — create one to run tests.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    ...environments.map(
                      (environment) => ExplorerTreeItem(
                        icon: Icons.memory_outlined,
                        label: environment.active
                            ? '${environment.name} ●'
                            : environment.name,
                        indent: 1,
                        selected: selectedEnvironment?.id == environment.id,
                        onTap: onSelectEnvironment == null
                            ? null
                            : () => onSelectEnvironment!(environment),
                      ),
                    ),
                ],
              ),
              ToolSection(
                title: 'Packages',
                children: [
                  ExplorerTreeItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Package Manager',
                    indent: 1,
                    onTap: onOpenPackageManager,
                  ),
                ],
              ),
              ToolSection(
                title: 'Reports',
                initiallyExpanded: recentRuns.isNotEmpty,
                children: [
                  ExplorerTreeItem(
                    icon: Icons.bar_chart_outlined,
                    label: 'Reports',
                    indent: 1,
                    onTap: onOpenReports,
                  ),
                  if (recentRuns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                      child: Text(
                        'No reports yet — run a suite to create one.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    ...recentRuns.take(5).map(
                          (run) => ExplorerTreeItem(
                            icon: Icons.play_circle_outline,
                            label: run.suite.isEmpty
                                ? run.projectName
                                : run.suite,
                            indent: 1,
                            onTap: onSelectReport == null
                                ? null
                                : () => onSelectReport!(run),
                          ),
                        ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
