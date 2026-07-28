class EnvironmentInfo {
  const EnvironmentInfo({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.pythonVersion,
    required this.pythonExecutable,
    required this.pipExecutable,
    required this.createdAt,
    required this.active,
    this.robotExecutable,
    this.robotVersion,
    this.packageCount = 0,
    this.platform,
    this.architecture,
    this.available = true,
  });

  factory EnvironmentInfo.fromJson(Map<String, dynamic> json) {
    return EnvironmentInfo(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      pythonVersion: json['python_version'] as String,
      pythonExecutable: json['python_executable'] as String,
      pipExecutable: json['pip_executable'] as String,
      robotExecutable: json['robot_executable'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      active: json['active'] as bool? ?? false,
      robotVersion: json['robot_version'] as String?,
      packageCount: (json['package_count'] as num?)?.toInt() ?? 0,
      platform: json['platform'] as String?,
      architecture: json['architecture'] as String?,
      available: json['available'] as bool? ?? true,
    );
  }

  final String id;
  final String workspaceId;
  final String name;
  final String path;
  final String pythonVersion;
  final String pythonExecutable;
  final String pipExecutable;
  final String? robotExecutable;
  final DateTime createdAt;
  final bool active;
  final String? robotVersion;
  final int packageCount;
  final String? platform;
  final String? architecture;
  final bool available;
}

class PythonInterpreterInfo {
  const PythonInterpreterInfo({
    required this.path,
    required this.version,
    required this.displayName,
  });

  factory PythonInterpreterInfo.fromJson(Map<String, dynamic> json) {
    return PythonInterpreterInfo(
      path: json['path'] as String,
      version: json['version'] as String,
      displayName: json['display_name'] as String? ??
          'Python ${json['version']} — ${json['path']}',
    );
  }

  final String path;
  final String version;
  final String displayName;
}

enum EnvironmentSort {
  active,
  name,
  createdAt;

  String get apiValue => switch (this) {
        EnvironmentSort.active => 'active',
        EnvironmentSort.name => 'name',
        EnvironmentSort.createdAt => 'created_at',
      };

  String get label => switch (this) {
        EnvironmentSort.active => 'Active',
        EnvironmentSort.name => 'Name',
        EnvironmentSort.createdAt => 'Created Date',
      };
}
