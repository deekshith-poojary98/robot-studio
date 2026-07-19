import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/project_info.dart';
import '../../core/gateway/models/workspace_info.dart';
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
              const ToolSection(
                title: 'Reports',
                initiallyExpanded: false,
                children: [
                  ExplorerTreeItem(
                    icon: Icons.folder_outlined,
                    label: 'No reports yet',
                    indent: 1,
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
