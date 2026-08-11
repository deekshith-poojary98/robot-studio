class RunVariableInfo {
  const RunVariableInfo({required this.key, this.value = ''});

  factory RunVariableInfo.fromJson(Map<String, dynamic> json) {
    return RunVariableInfo(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
    );
  }

  final String key;
  final String value;

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

class RunConfigurationInfo {
  const RunConfigurationInfo({
    required this.id,
    required this.name,
    this.environmentId,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.variables = const [],
    this.variableFiles = const [],
    this.extraRobotArgs = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory RunConfigurationInfo.fromJson(Map<String, dynamic> json) {
    return RunConfigurationInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      environmentId: json['environment_id'] as String?,
      includeTags: _stringList(json['include_tags']),
      excludeTags: _stringList(json['exclude_tags']),
      variables: (json['variables'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RunVariableInfo.fromJson)
          .toList(),
      variableFiles: _stringList(json['variable_files']),
      extraRobotArgs: _stringList(json['extra_robot_args']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String name;
  final String? environmentId;
  final List<String> includeTags;
  final List<String> excludeTags;
  final List<RunVariableInfo> variables;
  final List<String> variableFiles;
  final List<String> extraRobotArgs;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toWriteJson({bool activate = true}) {
    return {
      'name': name,
      'environment_id': environmentId,
      'include_tags': includeTags,
      'exclude_tags': excludeTags,
      'variables': [for (final item in variables) item.toJson()],
      'variable_files': variableFiles,
      'extra_robot_args': extraRobotArgs,
      'activate': activate,
    };
  }

  Map<String, dynamic> toPatchJson() {
    return {
      'name': name,
      'environment_id': environmentId,
      'clear_environment': environmentId == null,
      'include_tags': includeTags,
      'exclude_tags': excludeTags,
      'variables': [for (final item in variables) item.toJson()],
      'variable_files': variableFiles,
      'extra_robot_args': extraRobotArgs,
    };
  }
}

class RunConfigurationListInfo {
  const RunConfigurationListInfo({
    this.activeId,
    this.configurations = const [],
  });

  factory RunConfigurationListInfo.fromJson(Map<String, dynamic> json) {
    return RunConfigurationListInfo(
      activeId: json['active_id'] as String?,
      configurations: (json['configurations'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RunConfigurationInfo.fromJson)
          .toList(),
    );
  }

  final String? activeId;
  final List<RunConfigurationInfo> configurations;
}

class RunConfigurationDraft {
  const RunConfigurationDraft({
    required this.name,
    this.environmentId,
    this.includeTags = const [],
    this.excludeTags = const [],
    this.variables = const [],
    this.variableFiles = const [],
    this.extraRobotArgs = const [],
  });

  final String name;
  final String? environmentId;
  final List<String> includeTags;
  final List<String> excludeTags;
  final List<RunVariableInfo> variables;
  final List<String> variableFiles;
  final List<String> extraRobotArgs;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item.toString().trim().isNotEmpty) item.toString().trim(),
  ];
}
