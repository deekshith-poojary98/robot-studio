import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lightweight HTTP client for integration test setup and verification.
class IntegrationApiClient {
  IntegrationApiClient({this.baseUrl = 'http://127.0.0.1:8765/api/v1'});

  final String baseUrl;

  Future<Map<String, dynamic>> health() async {
    return _decode(await _get('/health'));
  }

  Future<Map<String, dynamic>> createWorkspace({
    required String name,
    required String location,
  }) async {
    return _decode(
      await _post('/workspaces', {'name': name, 'location': location}),
    );
  }

  Future<Map<String, dynamic>> openWorkspace(String path) async {
    return _decode(await _post('/workspaces/open', {'path': path}));
  }

  Future<List<Map<String, dynamic>>> listRecentWorkspaces() async {
    final body = _decode(await _get('/workspaces/recent'));
    return (body['workspaces'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createProject({
    required String name,
  }) async {
    return _decode(
      await _post('/projects', {'name': name}),
    );
  }

  Future<Map<String, dynamic>> openProject(String projectId) async {
    return _decode(
      await _post('/projects/open', {'project_id': projectId}),
    );
  }

  Future<Map<String, dynamic>> importProject(String path) async {
    return _decode(await _post('/projects/import', {'path': path}));
  }

  Future<List<Map<String, dynamic>>> listProjects() async {
    final body = _decode(await _get('/projects'));
    return (body['projects'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listRecentProjects() async {
    final body = _decode(await _get('/projects/recent'));
    return (body['projects'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listEnvironments() async {
    final body = _decode(await _get('/environments'));
    return (body['environments'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  }) async {
    return _decode(
      await _post('/environments', {
        'name': name,
        'python_interpreter': pythonInterpreter,
        'install_robot_framework': installRobotFramework,
      }),
    );
  }

  Future<Map<String, dynamic>> activateEnvironment(String id) async {
    return _decode(
      await _post('/environments/activate', {'environment_id': id}),
    );
  }

  Future<Map<String, dynamic>> importEnvironment(String path) async {
    return _decode(await _post('/environments/import', {'path': path}));
  }

  Future<Map<String, dynamic>> cloneEnvironment({
    required String id,
    required String name,
  }) async {
    return _decode(
      await _post('/environments/$id/clone', {'name': name}),
    );
  }

  Future<void> deleteEnvironment(String id, {bool deleteFiles = true}) async {
    await _delete('/environments/$id?delete_files=$deleteFiles');
  }

  Future<List<Map<String, dynamic>>> listPackages() async {
    final body = _decode(await _get('/packages'));
    return (body['packages'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> searchPackages(String query) async {
    return _decode(
      await _get('/packages/search?q=${Uri.encodeQueryComponent(query)}'),
    );
  }

  Future<Map<String, dynamic>> installPackage(String name) async {
    return _decode(await _post('/packages/install', {'name': name}));
  }

  Future<void> uninstallPackage(String name) async {
    await _post('/packages/uninstall', {'name': name});
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    return _decode(
      await _get('/files/content?path=${Uri.encodeQueryComponent(path)}'),
    );
  }

  Future<Map<String, dynamic>> writeFile({
    required String path,
    required String content,
  }) async {
    return _decode(
      await _put('/files/content', {'path': path, 'content': content}),
    );
  }

  Future<List<Map<String, dynamic>>> listFileTree({int depth = 4}) async {
    final body = _decode(await _get('/files/tree?depth=$depth'));
    return (body['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> runFile(String file) async {
    return _decode(await _post('/execution/run', {'file': file}));
  }

  Future<Map<String, dynamic>> runProject() async {
    return _decode(await _post('/execution/run-project', {}));
  }

  Future<Map<String, dynamic>> stopExecution() async {
    return _decode(await _post('/execution/stop', {}));
  }

  Future<Map<String, dynamic>> executionStatus() async {
    return _decode(await _get('/execution/status'));
  }

  Future<List<Map<String, dynamic>>> executionHistory() async {
    final body = _decode(await _get('/execution/history'));
    return (body['runs'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listReports() async {
    final body = _decode(await _get('/reports'));
    return (body['runs'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> reportsDashboard() async {
    return _decode(await _get('/reports/dashboard'));
  }

  Future<void> deleteReport(String runId) async {
    await _delete('/reports/$runId');
  }

  Future<Map<String, dynamic>> gitStatus() async {
    return _decode(await _get('/git/status'));
  }

  Future<Map<String, dynamic>> gitInit() async {
    return _decode(await _post('/git/init', {}));
  }

  Future<Map<String, dynamic>> gitCommit(String message) async {
    return _decode(await _post('/git/commit', {'message': message}));
  }

  Future<List<Map<String, dynamic>>> gitHistory() async {
    final response = await _get('/git/history?limit=20');
    final decoded = jsonDecode(response.body);
    return (decoded as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> gitCreateBranch(String name) async {
    return _decode(await _post('/git/create-branch', {'name': name}));
  }

  Future<Map<String, dynamic>> gitCheckout(String branch) async {
    return _decode(await _post('/git/checkout', {'branch': branch}));
  }

  Future<Map<String, dynamic>> gitFetch() async {
    return _decode(await _post('/git/fetch', {}));
  }

  Future<Map<String, dynamic>> gitPull() async {
    return _decode(await _post('/git/pull', {}));
  }

  Future<Map<String, dynamic>> gitPush() async {
    return _decode(await _post('/git/push', {}));
  }

  Future<Map<String, dynamic>> seedLocalGitRemote() async {
    return _decode(await _post('/git/seed-local-remote', {}));
  }

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final body = _decode(await _get('/plugins'));
    return (body['plugins'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> enablePlugin(String id) async {
    return _decode(await _post('/plugins/enable', {'id': id}));
  }

  Future<Map<String, dynamic>> disablePlugin(String id) async {
    return _decode(await _post('/plugins/disable', {'id': id}));
  }

  Future<Map<String, dynamic>> reloadPlugin(String id) async {
    return _decode(await _post('/plugins/reload', {'id': id}));
  }

  Future<List<Map<String, dynamic>>> refreshPlugins() async {
    final body = _decode(await _post('/plugins/refresh', {}));
    return (body['plugins'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> languageDiagnostics({
    required String filePath,
    required String content,
  }) async {
    return _decode(
      await _post('/language/diagnostics', {
        'file_path': filePath,
        'content': content,
      }),
    );
  }

  Future<Map<String, dynamic>> languageFormat({
    required String filePath,
    required String content,
  }) async {
    return _decode(
      await _post('/language/format', {
        'file_path': filePath,
        'content': content,
      }),
    );
  }

  Future<List<dynamic>> documentSymbols(String filePath) async {
    final body = _decode(
      await _get(
        '/language/document-symbols?file=${Uri.encodeQueryComponent(filePath)}',
      ),
    );
    return (body['results'] as List<dynamic>? ??
            body['symbols'] as List<dynamic>? ??
            const <dynamic>[]);
  }

  Future<Map<String, dynamic>> rebuildIndex() async {
    return _decode(await _post('/index/rebuild', {}));
  }

  Future<Map<String, dynamic>> indexStatus() async {
    return _decode(await _get('/index/status'));
  }

  Future<List<Map<String, dynamic>>> searchSymbols({
    String query = '',
    String? kind,
    int limit = 100,
  }) async {
    final buffer = StringBuffer(
      '/search/symbols?q=${Uri.encodeQueryComponent(query)}&limit=$limit',
    );
    if (kind != null) {
      buffer.write('&kind=${Uri.encodeQueryComponent(kind)}');
    }
    final body = _decode(await _get(buffer.toString()));
    return (body['results'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> languageCompletion({
    required String filePath,
    required String content,
    required int line,
    required int column,
    String query = '',
  }) async {
    return _decode(
      await _post('/language/completion', {
        'file_path': filePath,
        'content': content,
        'line': line,
        'column': column,
        'query': query,
      }),
    );
  }

  Future<Map<String, dynamic>?> languageHover({required String name}) async {
    final response = await _get(
      '/language/hover?name=${Uri.encodeQueryComponent(name)}',
    );
    if (response.statusCode == 200 &&
        (response.body.isEmpty || response.body == 'null')) {
      return null;
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>?> languageDefinition({required String name}) async {
    final response = await _get(
      '/language/definition?name=${Uri.encodeQueryComponent(name)}',
    );
    if (response.statusCode == 200 &&
        (response.body.isEmpty || response.body == 'null')) {
      return null;
    }
    return _decode(response);
  }

  Future<List<dynamic>> languageReferences({required String name}) async {
    final body = _decode(
      await _get(
        '/language/references?name=${Uri.encodeQueryComponent(name)}',
      ),
    );
    return (body['references'] as List<dynamic>? ?? const <dynamic>[]);
  }

  Future<IntegrationHttpResponse> _get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return IntegrationHttpResponse(response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  Future<IntegrationHttpResponse> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return IntegrationHttpResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<IntegrationHttpResponse> _put(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return IntegrationHttpResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _delete(String path) async {
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(Uri.parse('$baseUrl$path'));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.transform(utf8.decoder).join();
        throw HttpException('DELETE $path failed (${response.statusCode}): $text');
      }
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decode(IntegrationHttpResponse response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Object?;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw HttpException(
        detail ?? 'Request failed (${response.statusCode}): ${response.body}',
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw HttpException('Expected JSON object, got: ${response.body}');
  }
}

class IntegrationHttpResponse {
  IntegrationHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// Polls execution status until a terminal state is reached.
Future<Map<String, dynamic>> waitForExecutionFinished(
  IntegrationApiClient api, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await api.executionStatus();
    final state = status['status'] as String? ?? '';
    if (state == 'finished' || state == 'failed' || state == 'cancelled') {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Execution did not finish within ${timeout.inSeconds}s');
}
