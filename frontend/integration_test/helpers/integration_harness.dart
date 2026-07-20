import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/main.dart';

import 'backend_process.dart';
import 'integration_api_client.dart';
import 'performance_tracker.dart';
import 'ui_helpers.dart';

/// Shared lifecycle for Flutter integration tests.
class IntegrationHarness {
  IntegrationHarness();

  late final String repoRoot;
  late final TestResourceManager resources;
  late final Directory backendDataDir;
  BackendProcess? backend;
  late IntegrationApiClient api;
  final PerformanceTracker performance = PerformanceTracker();
  final List<FlutterErrorDetails> flutterErrors = [];
  bool _initialized = false;

  Future<void> setUpAll() async {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    repoRoot = findRepoRoot();
    resources = await TestResourceManager.create();
    backendDataDir = Directory('${resources.root.path}/backend-data');
    backendDataDir.createSync(recursive: true);

    final externalBackendUrl = backendUrlFromDefine();
    if (externalBackendUrl.isNotEmpty) {
      backend = BackendProcess.connectExternal(
        baseUrl: externalBackendUrl,
        dataDir: backendDataDir.path,
      );
      final ready = await BackendProcess.waitForHealth(
        '${backend!.baseUrl}/api/v1/health',
        timeout: const Duration(seconds: 45),
      );
      if (!ready) {
        throw StateError(
          'External backend at $externalBackendUrl did not become ready.',
        );
      }
    } else {
      backend = await performance.measureAsync(
        'backend_startup',
        () => BackendProcess.start(
          repoRoot: repoRoot,
          dataDir: backendDataDir,
        ),
      );
    }
    api = IntegrationApiClient(baseUrl: '${backend!.baseUrl}/api/v1');

    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousHandler?.call(details);
    };
    _initialized = true;
  }

  Future<void> tearDownAll() async {
    performance.logSummary();
    await backend?.stop();
    if (_initialized) {
      await resources.dispose();
    }
  }

  Future<void> launchApp(WidgetTester tester) async {
    flutterErrors.clear();
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await performance.measureAsync('app_launch', () async {
      await tester.pumpWidget(const RobotStudioApp());
      await waitForBackendReady(tester);
      await waitForWelcomeScreen(tester);
      return null;
    });
  }

  Future<void> launchAppWithWorkspace(
    WidgetTester tester, {
    required String workspaceName,
  }) async {
    await launchApp(tester);
    await openRecentWorkspace(tester, workspaceName);
  }

  Future<void> openRecentWorkspace(
    WidgetTester tester,
    String workspaceName,
  ) async {
    await tapText(tester, workspaceName);
    await pumpUntilFound(
      tester,
      find.text(workspaceName),
      timeout: const Duration(seconds: 20),
    );
  }

  Directory workspaceLocation(String suffix) {
    return resources.workspaceLocation(suffix);
  }

  Future<Map<String, dynamic>> seedWorkspace({
    required String name,
    String suffix = 'default',
  }) async {
    final location = workspaceLocation(suffix);
    return performance.measureAsync(
      'workspace_create_api',
      () => api.createWorkspace(name: name, location: location.path),
    );
  }

  Future<Map<String, dynamic>> seedProject({
    required String name,
    String type = 'empty',
  }) async {
    return api.createProject(name: name, type: type);
  }

  Future<Map<String, dynamic>> seedEnvironment({
    required String name,
    bool installRobot = true,
  }) async {
    return performance.measureAsync(
      'environment_create_api',
      () => api.createEnvironment(
        name: name,
        pythonInterpreter: defaultPythonInterpreter(),
        installRobotFramework: installRobot,
      ),
    );
  }

  void installTestPlugin(String workspacePath) {
    resources.installTestPlugin(workspacePath);
  }

  Future<void> configureGitRepo(String repoPath) async {
    final configPath = '$repoPath/.git/config';
    try {
      final existing = await api.readFile(configPath);
      var content = existing['content'] as String? ?? '';
      if (!content.contains('[user]')) {
        content = '$content\n[user]\n\temail = integration@test.local\n\tname = Integration Test\n';
        await api.writeFile(path: configPath, content: content);
      }
    } catch (_) {
      // Repository not initialized yet; configure after init in the test.
    }
  }

  Future<void> configureGitIdentityAfterInit(String repoPath) async {
    final configPath = '$repoPath/.git/config';
    final existing = await api.readFile(configPath);
    var content = existing['content'] as String? ?? '';
    if (!content.contains('[user]')) {
      content = '$content\n[user]\n\temail = integration@test.local\n\tname = Integration Test\n';
      await api.writeFile(path: configPath, content: content);
    }
  }

  void expectNoFlutterErrors() {
    expect(
      flutterErrors,
      isEmpty,
      reason: flutterErrors
          .map((item) => item.exceptionAsString())
          .join('\n'),
    );
  }
}
