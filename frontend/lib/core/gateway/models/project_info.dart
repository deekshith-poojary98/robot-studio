enum ProjectType {
  browser,
  api,
  selenium,
  empty,
  imported;

  String get apiValue => name;

  String get label => switch (this) {
        ProjectType.browser => 'Browser Automation',
        ProjectType.api => 'API Testing',
        ProjectType.selenium => 'Selenium',
        ProjectType.empty => 'Empty Project',
        ProjectType.imported => 'Imported',
      };

  static ProjectType fromApi(String value) {
    return ProjectType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ProjectType.empty,
    );
  }
}

class ProjectInfo {
  const ProjectInfo({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.type,
    required this.createdAt,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      type: ProjectType.fromApi(json['type'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String workspaceId;
  final String name;
  final String path;
  final ProjectType type;
  final DateTime createdAt;
}
