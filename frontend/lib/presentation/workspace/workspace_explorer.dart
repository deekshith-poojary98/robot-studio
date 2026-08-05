import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
import '../editor/document_outline.dart';
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
    this.fileRows = const [],
    this.isLoadingFileTree = false,
    this.selectedFilePath,
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
    this.outlineRoot,
    this.isLoadingOutline = false,
    this.selectedOutlineId,
    this.onOutlineSelect,
  });

  final WorkspaceInfo workspace;
  final List<ProjectInfo> projects;
  final bool isLoadingProjects;
  final ProjectInfo? selectedProject;
  final ValueChanged<ProjectInfo> onSelectProject;
  final VoidCallback onNewProject;
  final VoidCallback onImportProject;
  final List<FlatFileTreeRow> fileRows;
  final bool isLoadingFileTree;
  final String? selectedFilePath;
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
  final DocumentSymbolNode? outlineRoot;
  final bool isLoadingOutline;
  final String? selectedOutlineId;
  final ValueChanged<IndexedSymbolInfo>? onOutlineSelect;

  bool get _isSingleProjectRoot {
    if (projects.length != 1) return false;
    final project = projects.first;
    final projectPath = project.path.replaceAll('\\', '/');
    final workspacePath = workspace.path.replaceAll('\\', '/');
    return projectPath == workspacePath;
  }

  String get _filesRootPath {
    if (_isSingleProjectRoot) {
      return selectedProject?.path ?? projects.first.path;
    }
    return selectedProject?.path ?? workspace.path;
  }

  @override
  Widget build(BuildContext context) {
    final headerName = _isSingleProjectRoot
        ? (selectedProject?.name ?? projects.first.name)
        : (selectedProject?.name ?? workspace.name);

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        key: const Key('workspace-explorer-list'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
            child: TapRegion(
              groupId: kExplorerFileTreeTapGroup,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
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
                  if (onCreateEntry != null &&
                      onOpenFile != null &&
                      onToggleDirectory != null) ...[
                    IconButton(
                      key: const Key('explorer-new-file'),
                      tooltip: 'New File',
                      icon: const Icon(Icons.note_add_outlined, size: 15),
                      onPressed: () =>
                          fileTreeKey?.currentState?.beginNewFile(),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      key: const Key('explorer-new-folder'),
                      tooltip: 'New Folder',
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 15,
                      ),
                      onPressed: () =>
                          fileTreeKey?.currentState?.beginNewFolder(),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      key: const Key('explorer-collapse-all'),
                      tooltip: 'Collapse All Folders',
                      icon: const Icon(Icons.unfold_less, size: 15),
                      onPressed: onCollapseAllFolders,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
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
          if (onOpenFile != null && onToggleDirectory != null)
            Expanded(
              child: VirtualFileTree(
                key: fileTreeKey,
                rows: fileRows,
                isLoading: isLoadingFileTree,
                selectedPath: selectedFilePath,
                rootPath: _filesRootPath,
                onOpenFile: onOpenFile!,
                onToggleDirectory: onToggleDirectory!,
                gitFileStatuses: gitFileStatuses,
                emptyMessage: 'This project has no files yet.',
                emptyHint: 'Create a file to get started.',
                onEnsureExpanded: onEnsureExpanded,
                onCreateEntry: onCreateEntry,
                onRenameEntry: onRenameEntry,
                onDeleteEntry: onDeleteEntry,
                onDuplicateEntry: onDuplicateEntry,
                onMoveEntry: onMoveEntry,
                onCopyRelativePath: onCopyRelativePath,
                onCopyAbsolutePath: onCopyAbsolutePath,
                onRevealInOs: onRevealInOs,
              ),
            )
          else
            const Spacer(),
          DocumentOutlinePanel(
            embedded: true,
            root: outlineRoot,
            filePath: selectedFilePath ?? '',
            symbols: outline,
            isLoading: isLoadingOutline,
            selectedId: selectedOutlineId,
            onSelect: onOutlineSelect,
            // Leave room for the header and a usable slice of the file tree.
            maxHeight: constraints.hasBoundedHeight
                ? constraints.maxHeight - 140
                : null,
          ),
        ],
      ),
    );
  }
}
