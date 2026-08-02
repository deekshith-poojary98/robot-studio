class WorkspaceStreamEvent {
  const WorkspaceStreamEvent({
    required this.type,
    this.path,
    this.absolutePath,
    this.oldPath,
    this.oldAbsolutePath,
    this.isDirectory = false,
    this.scope,
    this.scopeId,
    this.reason,
    this.workspaceId,
    this.projectId,
    this.environmentId,
    this.message,
    this.current,
    this.total,
  });

  factory WorkspaceStreamEvent.fromJson(Map<String, dynamic> json) {
    return WorkspaceStreamEvent(
      type: json['type'] as String? ?? '',
      path: json['path'] as String?,
      absolutePath: json['absolute_path'] as String?,
      oldPath: json['old_path'] as String?,
      oldAbsolutePath: json['old_absolute_path'] as String?,
      isDirectory: json['is_directory'] as bool? ?? false,
      scope: json['scope'] as String?,
      scopeId: json['scope_id'] as String?,
      reason: json['reason'] as String?,
      workspaceId: json['workspace_id'] as String?,
      projectId: json['project_id'] as String?,
      environmentId: json['environment_id'] as String?,
      message: json['message'] as String?,
      current: (json['current'] as num?)?.toInt(),
      total: (json['total'] as num?)?.toInt(),
    );
  }

  final String type;
  final String? path;
  final String? absolutePath;
  final String? oldPath;
  final String? oldAbsolutePath;
  final bool isDirectory;
  final String? scope;
  final String? scopeId;
  final String? reason;
  final String? workspaceId;
  final String? projectId;
  final String? environmentId;
  final String? message;
  final int? current;
  final int? total;

  bool get isFilesystemEvent =>
      type.startsWith('FILE_') || type.startsWith('DIRECTORY_');

  bool get isRobotSource {
    final candidate = (absolutePath ?? path ?? '').toLowerCase();
    return candidate.endsWith('.robot') || candidate.endsWith('.resource');
  }
}
