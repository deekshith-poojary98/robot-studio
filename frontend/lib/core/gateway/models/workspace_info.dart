class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
}
