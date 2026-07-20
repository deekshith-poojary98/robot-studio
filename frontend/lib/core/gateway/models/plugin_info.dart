class PluginInfo {
  const PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.status,
    required this.enabled,
    this.author = '',
    this.description = '',
    this.capabilities = const [],
    this.path,
    this.isBuiltin = false,
    this.error,
    this.loadedAt,
  });

  factory PluginInfo.fromJson(Map<String, dynamic> json) {
    return PluginInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'loaded',
      enabled: json['enabled'] as bool? ?? false,
      capabilities: (json['capabilities'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      path: json['path'] as String?,
      isBuiltin: json['is_builtin'] as bool? ?? false,
      error: json['error'] as String?,
      loadedAt: json['loaded_at'] == null
          ? null
          : DateTime.parse(json['loaded_at'] as String),
    );
  }

  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String status;
  final bool enabled;
  final List<String> capabilities;
  final String? path;
  final bool isBuiltin;
  final String? error;
  final DateTime? loadedAt;

  bool get isFailed => status == 'failed';
}
