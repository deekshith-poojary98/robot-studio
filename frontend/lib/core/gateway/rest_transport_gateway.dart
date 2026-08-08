import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../logging/app_logger.dart';
import 'transport_gateway.dart';

export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/file_info.dart';
export 'models/git_info.dart';
export 'models/health_response.dart';
export 'models/index_info.dart';
export 'models/language_info.dart';
export 'models/library_info.dart';
export 'models/package_info.dart';
export 'models/plugin_info.dart';
export 'models/project_info.dart';
export 'models/report_info.dart';
export 'models/workspace_info.dart';

/// REST implementation of [TransportGateway].
class RestTransportGateway implements TransportGateway {
  RestTransportGateway({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? BackendConfig.httpBaseUrl,
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<HealthResponse> health() async {
    final response = await _get('/health', quiet: true);
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
    final response = await _post('/workspaces/open', body: {'path': path});
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
  Future<ProjectInfo> createProject({required String name}) async {
    final response = await _post('/projects', body: {'name': name});
    return ProjectInfo.fromJson(response);
  }

  @override
  Future<ProjectInfo> importProject(String path) async {
    final response = await _post('/projects/import', body: {'path': path});
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
  Future<OpenProjectByPathResult> openProjectByPath(
    String path, {
    bool force = false,
  }) async {
    final response = await _post(
      '/projects/open-path',
      body: {'path': path, 'force': force},
      timeout: const Duration(seconds: 60),
    );
    return OpenProjectByPathResult.fromJson(response);
  }

  @override
  Future<OpenProjectByPathResult> createStandaloneProject({
    required String name,
    required String location,
  }) async {
    final response = await _post(
      '/projects/standalone',
      body: {'name': name, 'location': location},
      timeout: const Duration(seconds: 60),
    );
    return OpenProjectByPathResult.fromJson(response);
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
    final response = await _post('/environments/import', body: {'path': path});
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
    final path = '/environments/$environmentId?delete_files=$deleteFiles';
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
  Future<PackageVersionList> listPackageVersions(String name) async {
    final encoded = Uri.encodeComponent(name);
    final response = await _get('/packages/$encoded/versions');
    return PackageVersionList.fromJson(response);
  }

  @override
  Future<PackageInfo> getPackage(String name) async {
    final encoded = Uri.encodeComponent(name);
    final response = await _get('/packages/$encoded');
    return PackageInfo.fromJson(response);
  }

  @override
  Future<PackageOperationResult> installPackage(
    String name, {
    String? version,
    bool force = false,
  }) async {
    final response = await _post(
      '/packages/install',
      body: {
        'name': name,
        if (version != null && version.isNotEmpty) 'version': version,
        if (force) 'force': true,
      },
      timeout: const Duration(minutes: 10),
    );
    return PackageOperationResult.fromJson(response);
  }

  @override
  Future<PackageOperationResult> installRequirements(String filePath) async {
    final response = await _post(
      '/packages/install-requirements',
      body: {'path': filePath},
      timeout: const Duration(minutes: 20),
    );
    return PackageOperationResult.fromJson(response);
  }

  @override
  Future<PackageOperationResult> exportRequirements(String filePath) async {
    final response = await _post(
      '/packages/export-requirements',
      body: {'path': filePath},
      timeout: const Duration(minutes: 5),
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
  Future<ExecutionInfo> runProject({bool confirm = false}) async {
    final response = await _post(
      '/execution/run-project',
      body: {'confirm': confirm},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<TestNodeInfo> getTestTree({String? query, bool lazy = true}) async {
    final params = <String>['lazy=${lazy ? 'true' : 'false'}'];
    if (query != null && query.isNotEmpty) {
      params.add('q=${Uri.encodeQueryComponent(query)}');
    }
    final response = await _get('/tests/tree?${params.join('&')}');
    return TestNodeInfo.fromJson(response['tree'] as Map<String, dynamic>);
  }

  @override
  Future<int> countTests({String? tag, bool projectWide = false}) async {
    final params = <String>['project_wide=${projectWide ? 'true' : 'false'}'];
    if (tag != null && tag.isNotEmpty) {
      params.add('tag=${Uri.encodeQueryComponent(tag)}');
    }
    final response = await _get('/tests/count?${params.join('&')}');
    return (response['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<TestNodeInfo>> getTestsForFile(String path) async {
    final response = await _get(
      '/tests/file?path=${Uri.encodeQueryComponent(path)}',
    );
    final items = response['nodes'] as List<dynamic>;
    return items
        .map((item) => TestNodeInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ExecutionInfo> runTest({
    required String file,
    required String name,
  }) async {
    final response = await _post(
      '/tests/run',
      body: {'file': file, 'name': name},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runTestSuite({
    String? file,
    bool confirm = false,
  }) async {
    final response = await _post(
      '/tests/run-suite',
      body: {'file': file, 'confirm': confirm},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runTestsByTag(
    String tag, {
    bool confirm = false,
  }) async {
    final response = await _post(
      '/tests/run-tag',
      body: {'tag': tag, 'confirm': confirm},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runFailedTests() async {
    final response = await _post(
      '/tests/run-failed',
      body: const {},
      timeout: const Duration(seconds: 30),
    );
    return ExecutionInfo.fromJson(response);
  }

  @override
  Future<ExecutionInfo> runSelectedTests(
    List<({String file, String name})> tests,
  ) async {
    final response = await _post(
      '/tests/run-selected',
      body: {
        'tests': [
          for (final item in tests) {'file': item.file, 'name': item.name},
        ],
      },
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
    final run = response['run'];
    if (run is Map<String, dynamic>) {
      return ExecutionInfo.fromJson(run);
    }
    // Idempotent no-op — nothing was running.
    return ExecutionInfo(
      id: '',
      workspaceId: '',
      projectId: '',
      environmentId: '',
      projectName: '',
      suite: '',
      status: ExecutionStatus.idle,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
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
  Future<String> openReportXml(String runId) async {
    final response = await _post('/reports/$runId/open-xml', body: {});
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
    final buffer = StringBuffer(
      '/search/symbols?q=${Uri.encodeQueryComponent(query)}&limit=$limit',
    );
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
  Future<ContentSearchResultInfo> searchContent({
    String query = '',
    int limit = 500,
    int contextLines = 1,
  }) async {
    final response = await _get(
      '/search/content?q=${Uri.encodeQueryComponent(query)}'
      '&limit=$limit&context_lines=$contextLines',
    );
    return ContentSearchResultInfo.fromJson(response);
  }

  @override
  Future<RunFailuresInfo> getRunFailures(String runId) async {
    final response = await _get(
      '/analysis/execution/run-failures'
      '?run_id=${Uri.encodeQueryComponent(runId)}',
    );
    return RunFailuresInfo.fromJson(response);
  }

  @override
  Future<IndexedSymbolInfo?> languageDefinition({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    if (filePath != null) {
      params.add('file=${Uri.encodeQueryComponent(filePath)}');
    }
    if (line != null) params.add('line=$line');
    if (column != null) params.add('column=$column');
    if (content != null) {
      params.add('content=${Uri.encodeQueryComponent(content)}');
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
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    if (filePath != null) {
      params.add('file=${Uri.encodeQueryComponent(filePath)}');
    }
    if (line != null) params.add('line=$line');
    if (column != null) params.add('column=$column');
    if (content != null) {
      params.add('content=${Uri.encodeQueryComponent(content)}');
    }
    final response = await _get('/language/references?${params.join('&')}');
    final items = response['references'] as List<dynamic>;
    return items
        .map(
          (item) => SymbolReferenceInfo.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    final params = <String>[];
    if (name != null) params.add('name=${Uri.encodeQueryComponent(name)}');
    if (symbolId != null) {
      params.add('symbol_id=${Uri.encodeQueryComponent(symbolId)}');
    }
    if (kind != null) {
      params.add('kind=${Uri.encodeQueryComponent(kind.apiValue)}');
    }
    if (filePath != null) {
      params.add('file=${Uri.encodeQueryComponent(filePath)}');
    }
    if (line != null) params.add('line=$line');
    if (column != null) params.add('column=$column');
    if (content != null) {
      params.add('content=${Uri.encodeQueryComponent(content)}');
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
  Future<DocumentAnalysisInfo> analyzeDocument({
    required String filePath,
    required String content,
  }) async {
    final response = await _post(
      '/language/document-analysis',
      body: {'file_path': filePath, 'content': content},
    );
    return DocumentAnalysisInfo.fromJson(response);
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
  Future<List<CompletionItemInfo>> languageCompletion({
    required String filePath,
    required int line,
    required int column,
    required String content,
    String query = '',
  }) async {
    final response = await _post(
      '/language/completion',
      body: {
        'file_path': filePath,
        'line': line,
        'column': column,
        'content': content,
        'query': query,
      },
    );
    final items = response['items'] as List<dynamic>;
    return items
        .map(
          (item) => CompletionItemInfo.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> languageCompletionUsage({
    required String label,
    String kind = '',
  }) async {
    await _post(
      '/language/completion/usage',
      body: {'label': label, 'kind': kind},
    );
  }

  @override
  Future<List<DiagnosticInfo>> languageDiagnostics({
    required String filePath,
    required String content,
  }) async {
    final response = await _post(
      '/language/diagnostics',
      body: {'file_path': filePath, 'content': content},
    );
    final items = response['diagnostics'] as List<dynamic>;
    return items
        .map((item) => DiagnosticInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> languageFormat({
    required String filePath,
    required String content,
    int? startLine,
    int? endLine,
  }) async {
    final body = <String, dynamic>{'file_path': filePath, 'content': content};
    if (startLine != null) body['start_line'] = startLine;
    if (endLine != null) body['end_line'] = endLine;
    final response = await _post('/language/format', body: body);
    return response['content'] as String;
  }

  @override
  Future<SignatureHelpInfo?> languageSignatureHelp({
    required String filePath,
    required int line,
    required int column,
    required String content,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/language/signature-help'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'file_path': filePath,
            'line': line,
            'column': column,
            'content': content,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200 &&
        (response.body.isEmpty || response.body == 'null')) {
      return null;
    }
    final decoded = _decode(response);
    return SignatureHelpInfo.fromJson(decoded);
  }

  @override
  Future<List<LibraryInfo>> languageLibraries() async {
    final response = await _get('/language/libraries');
    final items = response['libraries'] as List<dynamic>? ?? const [];
    return items
        .map((item) => LibraryInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<LibraryInfo?> languageLibrary(String name) async {
    final encoded = Uri.encodeComponent(name);
    final response = await _get('/language/libraries/$encoded');
    return LibraryInfo.fromJson(response);
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
  Future<FileMutationResult> createFile({
    required String path,
    String content = '',
  }) async {
    final response = await _post(
      '/files/create',
      body: {'path': path, 'content': content},
    );
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<FileMutationResult> createDirectory({required String path}) async {
    final response = await _post('/files/mkdir', body: {'path': path});
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<FileMutationResult> renamePath({
    required String path,
    required String newName,
  }) async {
    final response = await _post(
      '/files/rename',
      body: {'path': path, 'new_name': newName},
    );
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<FileMutationResult> movePath({
    required String path,
    required String destinationDir,
  }) async {
    final response = await _post(
      '/files/move',
      body: {'path': path, 'destination_dir': destinationDir},
    );
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<FileMutationResult> duplicatePath({required String path}) async {
    final response = await _post('/files/duplicate', body: {'path': path});
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<FileMutationResult> deletePath({required String path}) async {
    final response = await _post('/files/delete', body: {'path': path});
    return FileMutationResult.fromJson(response);
  }

  @override
  Future<List<FileTreeNode>> listFileTree({String? path, int depth = 0}) async {
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

  @override
  Future<List<PluginInfo>> listPlugins() async {
    final response = await _get('/plugins');
    final items = response['plugins'] as List<dynamic>;
    return items
        .map((item) => PluginInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PluginInfo>> refreshPlugins() async {
    final response = await _post('/plugins/refresh', body: {});
    final items = response['plugins'] as List<dynamic>;
    return items
        .map((item) => PluginInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PluginInfo?> getPlugin(String id) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/plugins/${Uri.encodeComponent(id)}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return null;
    return PluginInfo.fromJson(_decode(response));
  }

  @override
  Future<PluginInfo> enablePlugin(String id) async {
    final response = await _post('/plugins/enable', body: {'id': id});
    return PluginInfo.fromJson(response);
  }

  @override
  Future<PluginInfo> disablePlugin(String id) async {
    final response = await _post('/plugins/disable', body: {'id': id});
    return PluginInfo.fromJson(response);
  }

  @override
  Future<PluginInfo> reloadPlugin(String id) async {
    final response = await _post('/plugins/reload', body: {'id': id});
    return PluginInfo.fromJson(response);
  }

  @override
  Future<GitStatusInfo> getGitStatus() async {
    final response = await _get('/git/status');
    return GitStatusInfo.fromJson(response);
  }

  @override
  Future<GitRepositoryInfo> initGitRepository() async {
    final response = await _post('/git/init', body: {});
    return GitRepositoryInfo.fromJson(response);
  }

  @override
  Future<GitRepositoryInfo?> refreshGitRepository() async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/git/refresh'),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw GatewayException(
        detail ?? 'Request failed (${response.statusCode})',
      );
    }
    if (response.body.isEmpty || response.body == 'null') return null;
    return GitRepositoryInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<GitCommitInfo>> getGitHistory({int limit = 50}) async {
    final items = await _getArray('/git/history?limit=$limit');
    return items
        .map((item) => GitCommitInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<GitCommitDetailInfo> getGitCommitDetail(String commitHash) async {
    final response = await _get(
      '/git/history/${Uri.encodeComponent(commitHash)}',
    );
    return GitCommitDetailInfo.fromJson(response);
  }

  @override
  Future<List<GitBranchInfo>> getGitBranches() async {
    final items = await _getArray('/git/branches');
    return items
        .map((item) => GitBranchInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<GitRepositoryInfo> checkoutGitBranch(String branch) async {
    final response = await _post('/git/checkout', body: {'branch': branch});
    return GitRepositoryInfo.fromJson(response);
  }

  @override
  Future<GitBranchInfo> createGitBranch(
    String name, {
    String? startPoint,
  }) async {
    final body = <String, dynamic>{'name': name};
    if (startPoint != null) body['start_point'] = startPoint;
    final response = await _post('/git/create-branch', body: body);
    return GitBranchInfo.fromJson(response);
  }

  @override
  Future<void> deleteGitBranch(String name) async {
    await _post('/git/delete-branch', body: {'name': name});
  }

  @override
  Future<GitCommitInfo> commitGitChanges({
    required String message,
    List<String>? files,
  }) async {
    final body = <String, dynamic>{'message': message};
    if (files != null) body['files'] = files;
    final response = await _post('/git/commit', body: body);
    return GitCommitInfo.fromJson(response);
  }

  @override
  Future<GitRemoteResultInfo> fetchGit() async {
    final response = await _post('/git/fetch', body: {});
    return GitRemoteResultInfo.fromJson(response);
  }

  @override
  Future<GitRemoteResultInfo> pullGit() async {
    final response = await _post('/git/pull', body: {});
    return GitRemoteResultInfo.fromJson(response);
  }

  @override
  Future<GitRemoteResultInfo> pushGit() async {
    final response = await _post('/git/push', body: {});
    return GitRemoteResultInfo.fromJson(response);
  }

  @override
  Future<GitDiffInfo> getGitDiff({String? filePath, String? commit}) async {
    final buffer = StringBuffer('/git/diff?');
    if (filePath != null) {
      buffer.write('file=${Uri.encodeQueryComponent(filePath)}');
    }
    if (commit != null) {
      if (filePath != null) buffer.write('&');
      buffer.write('commit=${Uri.encodeQueryComponent(commit)}');
    }
    final response = await _get(buffer.toString());
    return GitDiffInfo.fromJson(response);
  }

  @override
  Future<DoctorProfilesBundle> getDoctorProfiles() async {
    final response = await _get('/doctor/profiles');
    return DoctorProfilesBundle.fromJson(response);
  }

  @override
  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  }) async {
    final body = <String, dynamic>{'profile': profile};
    if (projectId != null) body['project_id'] = projectId;
    if (providerIds != null) body['provider_ids'] = providerIds;
    final response = await _post('/doctor/run', body: body);
    return DoctorReport.fromJson(response);
  }

  @override
  Future<DoctorReport> getDoctorReport(String reportId) async {
    final response = await _get('/doctor/report/$reportId');
    return DoctorReport.fromJson(response);
  }

  @override
  Future<List<DoctorReportSummary>> getDoctorHistory({
    String? projectId,
    int limit = 20,
  }) async {
    final buffer = StringBuffer('/doctor/history?limit=$limit');
    if (projectId != null) {
      buffer.write('&project_id=${Uri.encodeQueryComponent(projectId)}');
    }
    final response = await _get(buffer.toString());
    final items = response['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => DoctorReportSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _get(String path, {bool quiet = false}) {
    return _send(
      'GET',
      path,
      () => _client
          .get(Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 30)),
      quiet: quiet,
    );
  }

  Future<List<dynamic>> _getArray(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'))
        .timeout(const Duration(seconds: 30));
    final decoded = response.body.isEmpty
        ? <dynamic>[]
        : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw GatewayException(
        detail ?? 'Request failed (${response.statusCode})',
      );
    }
    if (decoded is List<dynamic>) return decoded;
    throw GatewayException('Expected JSON array from $path');
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

  Future<Map<String, dynamic>> _patch(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _send(
      'PATCH',
      path,
      () => _client
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout),
      body: body,
    );
  }

  @override
  Future<AppSettings> getSettings() async {
    final response = await _get('/settings');
    return AppSettings.fromJson(response);
  }

  @override
  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    final response = await _patch('/settings', body: patch);
    return AppSettings.fromJson(response);
  }

  @override
  Future<AppSettings> resetSettings() async {
    final response = await _post('/settings/reset', body: {});
    return AppSettings.fromJson(response);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Future<http.Response> Function() send, {
    Map<String, dynamic>? body,
    bool allowEmpty = false,
    bool quiet = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (!quiet) {
      AppLogger.debug(
        '$method $path',
        tag: 'Gateway',
        data: body == null ? null : AppLogger.summarizeBody(body),
      );
    }
    try {
      final response = await send();
      stopwatch.stop();
      if (!quiet) {
        AppLogger.debug(
          '$method $path → ${response.statusCode} '
          '(${stopwatch.elapsedMilliseconds}ms, ${response.bodyBytes.length}b)',
          tag: 'Gateway',
        );
      }
      return _decode(response, allowEmpty: allowEmpty);
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (quiet) {
        AppLogger.debug(
          '$method $path failed after ${stopwatch.elapsedMilliseconds}ms',
          tag: 'Gateway',
          data: '$error',
        );
      } else {
        AppLogger.error(
          '$method $path failed after ${stopwatch.elapsedMilliseconds}ms',
          tag: 'Gateway',
          error: error,
          stackTrace: stackTrace,
        );
      }
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
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      if (detail is Map<String, dynamic>) {
        throw GatewayException(
          detail['message']?.toString() ?? detail.toString(),
          code: detail['code']?.toString(),
          count: (detail['count'] as num?)?.toInt(),
          threshold: (detail['threshold'] as num?)?.toInt(),
        );
      }
      final message =
          detail?.toString() ?? 'Request failed (${response.statusCode})';
      AppLogger.warn('HTTP ${response.statusCode}: $message', tag: 'Gateway');
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
