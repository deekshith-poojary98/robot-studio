import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/execution_info.dart';
import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../git/history_panel.dart';
import '../project/project_details_panel.dart';
import '../widgets/explorer_tree.dart';

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
    this.fileTree = const [],
    this.onOpenFile,
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
  final List<FileTreeNode> fileTree;
  final ValueChanged<String>? onOpenFile;
  final Map<String, GitFileStatus> gitFileStatuses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workspace.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                workspace.path,
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
                'WORKSPACE',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
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
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('workspace-explorer-list'),
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ToolSection(
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
                        icon: iconForProjectType(project.type),
                        label: project.name,
                        indent: 1,
                        selected: selectedProject?.id == project.id,
                        onTap: () => onSelectProject(project),
                      ),
                    ),
                ],
              ),
              if (onOpenFile != null)
                ToolSection(
                  title: 'Files',
                  initiallyExpanded: fileTree.isNotEmpty,
                  children: fileTree.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 4, 12, 8),
                            child: Text(
                              'No source files found.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ]
                      : [
                          for (final node in fileTree)
                            _FileTreeNodeTile(
                              node: node,
                              indent: 1,
                              onOpenFile: onOpenFile!,
                              gitFileStatuses: gitFileStatuses,
                            ),
                        ],
                ),
              const ToolSection(
                title: 'Shared',
                children: [
                  ExplorerTreeItem(
                    icon: Icons.folder_outlined,
                    label: 'Resources',
                    indent: 1,
                  ),
                  ExplorerTreeItem(
                    icon: Icons.folder_outlined,
                    label: 'Variables',
                    indent: 1,
                  ),
                ],
              ),
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
                        'No environments yet',
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
                        'No reports yet',
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

class _FileTreeNodeTile extends StatefulWidget {
  const _FileTreeNodeTile({
    required this.node,
    required this.indent,
    required this.onOpenFile,
    required this.gitFileStatuses,
  });

  final FileTreeNode node;
  final int indent;
  final ValueChanged<String> onOpenFile;
  final Map<String, GitFileStatus> gitFileStatuses;

  @override
  State<_FileTreeNodeTile> createState() => _FileTreeNodeTileState();
}

class _FileTreeNodeTileState extends State<_FileTreeNodeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    if (node.isDir) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExplorerTreeItem(
            icon: _expanded
                ? Icons.folder_open_outlined
                : Icons.folder_outlined,
            label: node.name,
            indent: widget.indent,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            for (final child in node.children)
              _FileTreeNodeTile(
                node: child,
                indent: widget.indent + 1,
                onOpenFile: widget.onOpenFile,
                gitFileStatuses: widget.gitFileStatuses,
              ),
        ],
      );
    }

    if (!node.isRobotSource) return const SizedBox.shrink();

    final gitStatus = _gitStatusForNode(node);

    return ExplorerTreeItem(
      icon: _iconForSuffix(node.suffix),
      label: node.name,
      indent: widget.indent,
      trailing: gitStatus == null ? null : GitStatusBadge(status: gitStatus),
      onTap: () => widget.onOpenFile(node.path),
    );
  }

  GitFileStatus? _gitStatusForNode(FileTreeNode node) {
    for (final entry in widget.gitFileStatuses.entries) {
      if (node.path.endsWith(entry.key) ||
          node.relativePath == entry.key ||
          node.path.endsWith('/${entry.key}')) {
        return entry.value;
      }
    }
    return null;
  }

  IconData _iconForSuffix(String suffix) {
    return switch (suffix) {
      '.py' => Icons.code_outlined,
      '.resource' => Icons.library_books_outlined,
      _ => Icons.description_outlined,
    };
  }
}
