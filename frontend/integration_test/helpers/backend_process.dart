import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts and stops the Robot Studio Python backend for integration tests.
class BackendProcess {
  BackendProcess._({
    required this.baseUrl,
    required this.dataDir,
    this.process,
    this.managedExternally = false,
  });

  final Process? process;
  final String baseUrl;
  final String dataDir;
  final bool managedExternally;

  static const defaultBaseUrl = 'http://127.0.0.1:8765';

  /// Connects to a backend started outside the Flutter app process.
  ///
  /// Required on macOS where the app sandbox blocks spawning Python.
  static BackendProcess connectExternal({
    String baseUrl = defaultBaseUrl,
    required String dataDir,
  }) {
    return BackendProcess._(
      baseUrl: baseUrl,
      dataDir: dataDir,
      managedExternally: true,
    );
  }

  static Future<BackendProcess> start({
    required String repoRoot,
    required Directory dataDir,
    String? pythonExecutable,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    dataDir.createSync(recursive: true);

    final python = pythonExecutable ?? _resolvePython(repoRoot);
    if (python != 'python3' &&
        python != 'python' &&
        !File(python).existsSync()) {
      throw StateError(
        'Python interpreter not found at $python. '
        'Create backend/.venv or set ROBOT_STUDIO_PYTHON.',
      );
    }

    final backendDir = Directory('$repoRoot/backend');
    if (!backendDir.existsSync()) {
      throw StateError('Backend directory not found: ${backendDir.path}');
    }

    late final Process process;
    try {
      process = await Process.start(
        python,
        ['-m', 'robot_studio.main'],
        workingDirectory: backendDir.path,
        environment: {
          ...Platform.environment,
          'ROBOT_STUDIO_DATA_DIR': dataDir.path,
          'ROBOT_STUDIO_HOST': '127.0.0.1',
          'ROBOT_STUDIO_PORT': '8765',
        },
      );
    } on ProcessException catch (error) {
      throw StateError(
        'Could not start backend subprocess (${error.message}). '
        'On macOS desktop integration tests, run '
        './scripts/run_integration_tests.sh instead.',
      );
    }

    final stderrBuffer = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

    final ready = await waitForHealth(
      '$defaultBaseUrl/api/v1/health',
      timeout: timeout,
    );
    if (!ready) {
      process.kill();
      throw StateError(
        'Backend failed to become ready within ${timeout.inSeconds}s.\n'
        '${stderrBuffer.toString()}',
      );
    }

    return BackendProcess._(
      process: process,
      baseUrl: defaultBaseUrl,
      dataDir: dataDir.path,
    );
  }

  Future<void> stop() async {
    if (managedExternally || process == null) {
      return;
    }

    process!.kill(ProcessSignal.sigterm);
    try {
      await process!.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process!.kill(ProcessSignal.sigkill);
    }
  }

  static String _resolvePython(String repoRoot) {
    final fromEnv = Platform.environment['ROBOT_STUDIO_PYTHON'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }

    final candidates = [
      '$repoRoot/backend/.venv/bin/python',
      '$repoRoot/backend/.venv/Scripts/python.exe',
      'python3',
      'python',
    ];
    for (final candidate in candidates) {
      if (candidate == 'python3' || candidate == 'python') {
        return candidate;
      }
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return 'python3';
  }

  static Future<bool> waitForHealth(
    String url, {
    required Duration timeout,
  }) async {
    final client = HttpClient();
    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode == 200) {
            return true;
          }
        } catch (_) {
          // Backend still starting.
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

bool _isRepoRoot(Directory dir) {
  return File('${dir.path}/backend/pyproject.toml').existsSync();
}

/// Reads compile-time repo root passed via `--dart-define`.
String repoRootFromDefine() {
  return const String.fromEnvironment('ROBOT_STUDIO_REPO_ROOT');
}

/// Reads compile-time backend URL passed via `--dart-define`.
String backendUrlFromDefine() {
  return const String.fromEnvironment('INTEGRATION_BACKEND_URL');
}

/// Locates the repository root from compile-time defines, environment, or paths.
String findRepoRoot() {
  const fromDefine = String.fromEnvironment('ROBOT_STUDIO_REPO_ROOT');
  if (fromDefine.isNotEmpty && _isRepoRoot(Directory(fromDefine))) {
    return fromDefine;
  }

  final fromEnv = Platform.environment['ROBOT_STUDIO_REPO_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty && _isRepoRoot(Directory(fromEnv))) {
    return fromEnv;
  }

  final starts = <Directory>{Directory.current};
  try {
    var scriptDir = File(Platform.script.toFilePath()).parent;
    starts.add(scriptDir);
    for (var i = 0; i < 4; i++) {
      starts.add(scriptDir);
      scriptDir = scriptDir.parent;
    }
  } catch (_) {
    // Platform.script may be unavailable in some embed contexts.
  }

  for (final start in starts) {
    var dir = start;
    for (var i = 0; i < 10; i++) {
      if (_isRepoRoot(dir)) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
  }

  throw StateError(
    'Could not locate repository root (backend/pyproject.toml). '
    'Use ./scripts/run_integration_tests.sh or pass '
    '--dart-define=ROBOT_STUDIO_REPO_ROOT=<path>.',
  );
}
