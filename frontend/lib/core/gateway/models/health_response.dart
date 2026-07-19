class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.version,
    required this.modules,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    return HealthResponse(
      status: json['status'] as String,
      version: json['version'] as String,
      modules: (json['modules'] as List<dynamic>).cast<String>(),
    );
  }

  final String status;
  final String version;
  final List<String> modules;
}
