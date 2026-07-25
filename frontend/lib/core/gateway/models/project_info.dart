import 'workspace_info.dart';

/// Persistence tag from the API — not shown as a product "project type".
enum ProjectKind {
  empty,
  imported;

  static ProjectKind fromApi(String? value) {
    if (value == 'imported') return ProjectKind.imported;
    return ProjectKind.empty;
  }
}

class ProjectInfo {
  const ProjectInfo({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.createdAt,
    this.kind = ProjectKind.empty,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      kind: ProjectKind.fromApi(json['type'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String workspaceId;
  final String name;
  final String path;
  final ProjectKind kind;
  final DateTime createdAt;
}

class OpenProjectByPathResult {
  const OpenProjectByPathResult({
    required this.workspace,
    required this.project,
    this.needsEnvironment = false,
    this.detectedEnvironments = const [],
  });

  factory OpenProjectByPathResult.fromJson(Map<String, dynamic> json) {
    final detected = json['detected_environments'] as List<dynamic>? ?? const [];
    return OpenProjectByPathResult(
      workspace: WorkspaceInfo.fromJson(
        json['workspace'] as Map<String, dynamic>,
      ),
      project: ProjectInfo.fromJson(
        json['project'] as Map<String, dynamic>,
      ),
      needsEnvironment: json['needs_environment'] as bool? ?? false,
      detectedEnvironments: detected
          .map(
            (item) => DetectedEnvironmentInfo.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  final WorkspaceInfo workspace;
  final ProjectInfo project;
  final bool needsEnvironment;
  final List<DetectedEnvironmentInfo> detectedEnvironments;
}

class DetectedEnvironmentInfo {
  const DetectedEnvironmentInfo({
    required this.name,
    required this.path,
  });

  factory DetectedEnvironmentInfo.fromJson(Map<String, dynamic> json) {
    return DetectedEnvironmentInfo(
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }

  final String name;
  final String path;
}
