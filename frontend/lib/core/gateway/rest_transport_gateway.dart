import 'dart:convert';

import 'package:http/http.dart' as http;

import 'transport_gateway.dart';

export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/health_response.dart';
export 'models/package_info.dart';
export 'models/project_info.dart';
export 'models/workspace_info.dart';

/// REST implementation of [TransportGateway].
class RestTransportGateway implements TransportGateway {
  RestTransportGateway({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? 'http://127.0.0.1:8765/api/v1',
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<HealthResponse> health() async {
    final response = await _get('/health');
    return HealthResponse.fromJson(response);
  }

  @override
  Future<WorkspaceInfo> createWorkspace({
    required String name,
    required String location,
  }) async {
    final response = await _post(
      '/workspaces',
      body: {'name': name, 'location': location},
    );
    return WorkspaceInfo.fromJson(response);
  }

  @override
  Future<WorkspaceInfo> openWorkspace(String path) async {
    final response = await _post(
      '/workspaces/open',
      body: {'path': path},
    );
    return WorkspaceInfo.fromJson(response);
  }

  @override
  Future<List<WorkspaceInfo>> listRecentWorkspaces() async {
    final response = await _get('/workspaces/recent');
    final items = response['workspaces'] as List<dynamic>;
    return items
        .map((item) => WorkspaceInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ProjectInfo> createProject({
    required String name,
    required ProjectType type,
  }) async {
    final response = await _post(
      '/projects',
      body: {'name': name, 'type': type.apiValue},
    );
    return ProjectInfo.fromJson(response);
  }

  @override
  Future<ProjectInfo> importProject(String path) async {
    final response = await _post(
      '/projects/import',
      body: {'path': path},
    );
    return ProjectInfo.fromJson(response);
  }

  @override
  Future<List<ProjectInfo>> listProjects() async {
    final response = await _get('/projects');
    final items = response['projects'] as List<dynamic>;
    return items
        .map((item) => ProjectInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ProjectInfo> openProject(String projectId) async {
    final response = await _post(
      '/projects/open',
      body: {'project_id': projectId},
    );
    return ProjectInfo.fromJson(response);
  }

  @override
  Future<List<ProjectInfo>> listRecentProjects() async {
    final response = await _get('/projects/recent');
    final items = response['projects'] as List<dynamic>;
    return items
        .map((item) => ProjectInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<EnvironmentInfo>> listEnvironments({
    EnvironmentSort sort = EnvironmentSort.active,
  }) async {
    final response = await _get('/environments?sort=${sort.apiValue}');
    final items = response['environments'] as List<dynamic>;
    return items
        .map((item) => EnvironmentInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<EnvironmentInfo> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  }) async {
    final response = await _post(
      '/environments',
      body: {
        'name': name,
        'python_interpreter': pythonInterpreter,
        'install_robot_framework': installRobotFramework,
      },
      timeout: const Duration(minutes: 5),
    );
    return EnvironmentInfo.fromJson(response);
  }

  @override
  Future<EnvironmentInfo> importEnvironment(String path) async {
    final response = await _post(
      '/environments/import',
      body: {'path': path},
    );
    return EnvironmentInfo.fromJson(response);
  }

  @override
  Future<EnvironmentInfo> activateEnvironment(String environmentId) async {
    final response = await _post(
      '/environments/activate',
      body: {'environment_id': environmentId},
    );
    return EnvironmentInfo.fromJson(response);
  }

  @override
  Future<EnvironmentInfo> getEnvironment(String environmentId) async {
    final response = await _get('/environments/$environmentId');
    return EnvironmentInfo.fromJson(response);
  }

  @override
  Future<EnvironmentInfo> cloneEnvironment({
    required String environmentId,
    required String name,
  }) async {
    final response = await _post(
      '/environments/$environmentId/clone',
      body: {'name': name},
      timeout: const Duration(minutes: 5),
    );
    return EnvironmentInfo.fromJson(response);
  }

  @override
  Future<void> deleteEnvironment({
    required String environmentId,
    bool deleteFiles = false,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/environments/$environmentId?delete_files=$deleteFiles',
    );
    final response = await _client
        .delete(uri)
        .timeout(const Duration(seconds: 30));
    _decode(response, allowEmpty: true);
  }

  @override
  Future<PackageListResult> listPackages({
    String? query,
    PackageSort sort = PackageSort.name,
  }) async {
    final buffer = StringBuffer('/packages?sort=${sort.apiValue}');
    if (query != null && query.trim().isNotEmpty) {
      buffer.write('&q=${Uri.encodeQueryComponent(query.trim())}');
    }
    final response = await _get(buffer.toString());
    return PackageListResult.fromJson(response);
  }

  @override
  Future<List<PackageSearchResult>> searchPackages(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final response = await _get('/packages/search?q=$encoded');
    final items = response['results'] as List<dynamic>;
    return items
        .map(
          (item) => PackageSearchResult.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<PackageInfo> getPackage(String name) async {
    final encoded = Uri.encodeComponent(name);
    final response = await _get('/packages/$encoded');
    return PackageInfo.fromJson(response);
  }

  @override
  Future<PackageOperationResult> installPackage(String name) async {
    final response = await _post(
      '/packages/install',
      body: {'name': name},
      timeout: const Duration(minutes: 10),
    );
    return PackageOperationResult.fromJson(response);
  }

  @override
  Future<PackageOperationResult> updatePackage(String name) async {
    final response = await _post(
      '/packages/update',
      body: {'name': name},
      timeout: const Duration(minutes: 10),
    );
    return PackageOperationResult.fromJson(response);
  }

  @override
  Future<PackageOperationResult> uninstallPackage(String name) async {
    final response = await _post(
      '/packages/uninstall',
      body: {'name': name},
      timeout: const Duration(minutes: 5),
    );
    return PackageOperationResult.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runFile({String? file}) async {
    final response = await _post(
      '/execution/run',
      body: {'file': file},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runProject() async {
    final response = await _post(
      '/execution/run-project',
      body: const {},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> stopExecution() async {
    final response = await _post(
      '/execution/stop',
      body: const {},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionStatusInfo> getExecutionStatus() async {
    final response = await _get('/execution/status');
    return ExecutionStatusInfo.fromJson(response);
  }

  @override
  Future<List<ExecutionInfo>> listExecutionHistory() async {
    final response = await _get('/execution/history');
    final items = response['runs'] as List<dynamic>;
    return items
        .map((item) => ExecutionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'))
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(
    http.Response response, {
    bool allowEmpty = false,
  }) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Object?;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw GatewayException(
        detail ?? 'Request failed (${response.statusCode})',
      );
    }

    if (allowEmpty && response.body.isEmpty) {
      return <String, dynamic>{};
    }

    if (decoded is! Map<String, dynamic>) {
      throw GatewayException('Unexpected response from backend');
    }
    return decoded;
  }
}
