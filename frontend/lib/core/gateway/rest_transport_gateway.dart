import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logging/app_logger.dart';
import 'transport_gateway.dart';

export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/file_info.dart';
export 'models/health_response.dart';
export 'models/index_info.dart';
export 'models/package_info.dart';
export 'models/project_info.dart';
export 'models/report_info.dart';
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
  Future<List<PythonInterpreterInfo>> listPythonInterpreters() async {
    final response = await _get('/environments/interpreters');
    final items = response['interpreters'] as List<dynamic>;
    return items
        .map(
          (item) =>
              PythonInterpreterInfo.fromJson(item as Map<String, dynamic>),
        )
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
    final path =
        '/environments/$environmentId?delete_files=$deleteFiles';
    await _send(
      'DELETE',
      path,
      () => _client
          .delete(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 30)),
      allowEmpty: true,
    );
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

  @override
  Future<List<ExecutionInfo>> listReports() async {
    final response = await _get('/reports');
    final items = response['runs'] as List<dynamic>;
    return items
        .map((item) => ExecutionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ExecutionInfo> getReport(String runId) async {
    final response = await _get('/reports/$runId');
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<void> deleteReport(String runId) async {
    final path = '/reports/$runId';
    await _send(
      'DELETE',
      path,
      () => _client
          .delete(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 30)),
      allowEmpty: true,
    );
  }

  @override
  Future<String> openReportLog(String runId) async {
    final response = await _post('/reports/$runId/open-log', body: {});
    return response['path'] as String? ?? '';
  }

  @override
  Future<String> openReportHtml(String runId) async {
    final response = await _post('/reports/$runId/open-report', body: {});
    return response['path'] as String? ?? '';
  }

  @override
  Future<String> revealReport(String runId) async {
    final response = await _post('/reports/$runId/reveal', body: {});
    return response['path'] as String? ?? '';
  }

  @override
  Future<DashboardSummary> getReportsDashboard() async {
    final response = await _get('/reports/dashboard');
    return DashboardSummary.fromJson(response);
  }

  @override
  Future<IndexStatusInfo> rebuildIndex() async {
    final response = await _post('/index/rebuild', body: {});
    return IndexStatusInfo.fromJson(response);
  }

  @override
  Future<IndexStatusInfo> getIndexStatus() async {
    final response = await _get('/index/status');
    return IndexStatusInfo.fromJson(response);
  }

  @override
  Future<List<IndexedSymbolInfo>> searchSymbols({
    String query = '',
    SymbolKind? kind,
    int limit = 100,
  }) async {
    final buffer = StringBuffer('/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit');
    if (kind != null) {
      buffer.write('&kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    final response = await _get(buffer.toString());
    final items = response['results'] as List<dynamic>;
    return items
        .map((item) => IndexedSymbolInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<IndexedSymbolInfo?> languageDefinition({
    String? name,
    String? symbolId,
    SymbolKind? kind,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    final response = await _client
        .get(Uri.parse('$baseUrl/language/definition?${params.join('&')}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200 && response.body.isEmpty) {
      return null;
    }
    if (response.statusCode == 200 && response.body == 'null') {
      return null;
    }
    final decoded = _decode(response);
    return IndexedSymbolInfo.fromJson(decoded);
  }

  @override
  Future<List<SymbolReferenceInfo>> languageReferences({
    String? name,
    String? symbolId,
    SymbolKind? kind,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    final response = await _get('/language/references?${params.join('&')}');
    final items = response['references'] as List<dynamic>;
    return items
        .map((item) => SymbolReferenceInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    final response = await _client
        .get(Uri.parse('$baseUrl/language/hover?${params.join('&')}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200 &&
        (response.body.isEmpty || response.body == 'null')) {
      return null;
    }
    final decoded = _decode(response);
    return HoverInfo.fromJson(decoded);
  }

  @override
  Future<List<IndexedSymbolInfo>> documentSymbols(String filePath) async {
    final response = await _get(
      '/language/document-symbols?file=${Uri.encodeQueryComponent(filePath)}',
    );
    final items = response['results'] as List<dynamic>;
    return items
        .map((item) => IndexedSymbolInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<IndexedSymbolInfo>> workspaceSymbols({
    String query = '',
    int limit = 200,
  }) async {
    final response = await _get(
      '/language/workspace-symbols?q=${Uri.encodeQueryComponent(query)}&limit=$limit',
    );
    final items = response['results'] as List<dynamic>;
    return items
        .map((item) => IndexedSymbolInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<FileContentInfo> readFile(String path) async {
    final response = await _get(
      '/files/content?path=${Uri.encodeQueryComponent(path)}',
    );
    return FileContentInfo.fromJson(response);
  }

  @override
  Future<FileWriteResult> writeFile({
    required String path,
    required String content,
  }) async {
    final response = await _put(
      '/files/content',
      body: {'path': path, 'content': content},
    );
    return FileWriteResult.fromJson(response);
  }

  @override
  Future<List<FileTreeNode>> listFileTree({
    String? path,
    int depth = 3,
  }) async {
    final buffer = StringBuffer('/files/tree?depth=$depth');
    if (path != null) {
      buffer.write('&path=${Uri.encodeQueryComponent(path)}');
    }
    final response = await _get(buffer.toString());
    final items = response['entries'] as List<dynamic>;
    return items
        .map((item) => FileTreeNode.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _get(String path) {
    return _send(
      'GET',
      path,
      () => _client
          .get(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 30)),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _send(
      'POST',
      path,
      () => _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout),
      body: body,
    );
  }

  Future<Map<String, dynamic>> _put(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _send(
      'PUT',
      path,
      () => _client
          .put(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout),
      body: body,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Future<http.Response> Function() send, {
    Map<String, dynamic>? body,
    bool allowEmpty = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.debug(
      '$method $path',
      tag: 'Gateway',
      data: body == null ? null : AppLogger.summarizeBody(body),
    );
    try {
      final response = await send();
      stopwatch.stop();
      AppLogger.debug(
        '$method $path → ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms, ${response.bodyBytes.length}b)',
        tag: 'Gateway',
      );
      return _decode(response, allowEmpty: allowEmpty);
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLogger.error(
        '$method $path failed after ${stopwatch.elapsedMilliseconds}ms',
        tag: 'Gateway',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
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
      final message = detail ?? 'Request failed (${response.statusCode})';
      AppLogger.warn(
        'HTTP ${response.statusCode}: $message',
        tag: 'Gateway',
      );
      throw GatewayException(message);
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
