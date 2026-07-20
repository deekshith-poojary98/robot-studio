import '../../../core/gateway/transport_gateway.dart';
import '../../../core/logging/app_logger.dart';
import 'shell_controller.dart';

class WorkspaceShellController {
  WorkspaceShellController({
    required this.gateway,
    required this.notify,
    required this.isMounted,
    required this.appendLog,
  });

  final TransportGateway gateway;
  final ShellNotify notify;
  final ShellMounted isMounted;
  final void Function(String line) appendLog;

  String backendStatus = 'connecting';
  String? backendVersion;
  List<String> logLines = [];

  WorkspaceInfo? activeWorkspace;
  ProjectInfo? selectedProject;
  EnvironmentInfo? selectedEnvironment;
  List<ProjectInfo> projects = [];
  List<EnvironmentInfo> environments = [];
  List<WorkspaceInfo> recentWorkspaces = [];
  List<ProjectInfo> recentProjects = [];
  bool loadingRecent = true;
  bool loadingProjects = false;
  bool loadingEnvironments = false;
  bool busy = false;

  EnvironmentInfo? get activeEnvironment {
    for (final environment in environments) {
      if (environment.active) return environment;
    }
    return null;
  }

  bool get backendConnected => backendStatus == 'connected';

  Future<void> checkBackend({
    required Future<void> Function() onConnected,
  }) async {
    AppLogger.debug('Checking backend health', tag: 'Shell');
    try {
      final health = await gateway.health();
      if (!isMounted()) return;
      backendStatus = 'connected';
      backendVersion = health.version;
      logLines = [
        '[info] Connected to backend v${health.version}',
        '[info] ${health.modules.length} modules registered',
      ];
      notify();
      for (final line in logLines) {
        AppLogger.fromConsoleLine(line, tag: 'Shell');
      }
      await onConnected();
    } catch (error, stackTrace) {
      if (!isMounted()) return;
      AppLogger.error(
        'Backend unavailable',
        tag: 'Shell',
        error: error,
        stackTrace: stackTrace,
      );
      backendStatus = 'offline';
      logLines = [
        '[error] Backend unavailable: $error',
        '[info] Start the backend with: python -m robot_studio.main',
      ];
      notify();
    }
  }

  Future<void> loadRecent() async {
    if (!backendConnected) {
      loadingRecent = false;
      recentWorkspaces = [];
      recentProjects = [];
      notify();
      return;
    }

    loadingRecent = true;
    notify();
    try {
      recentWorkspaces = await gateway.listRecentWorkspaces();
      recentProjects = await gateway.listRecentProjects();
      if (!isMounted()) return;
      loadingRecent = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingRecent = false;
      appendLog('[warn] Could not load recent items: $error');
      notify();
    }
  }

  Future<void> loadProjects() async {
    if (activeWorkspace == null || !backendConnected) {
      projects = [];
      loadingProjects = false;
      notify();
      return;
    }

    loadingProjects = true;
    notify();
    try {
      projects = await gateway.listProjects();
      if (!isMounted()) return;
      loadingProjects = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingProjects = false;
      appendLog('[warn] Could not load projects: $error');
      notify();
    }
  }

  Future<void> loadEnvironments({EnvironmentSort sort = EnvironmentSort.active}) async {
    if (activeWorkspace == null || !backendConnected) {
      environments = [];
      loadingEnvironments = false;
      selectedEnvironment = null;
      notify();
      return;
    }

    loadingEnvironments = true;
    notify();
    try {
      environments = await gateway.listEnvironments(sort: sort);
      if (!isMounted()) return;
      loadingEnvironments = false;
      if (selectedEnvironment != null) {
        final match = environments
            .where((item) => item.id == selectedEnvironment!.id)
            .toList();
        selectedEnvironment = match.isEmpty ? null : match.first;
      }
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingEnvironments = false;
      appendLog('[warn] Could not load environments: $error');
      notify();
    }
  }

  void append(String line) {
    AppLogger.fromConsoleLine(line, tag: 'Shell');
    logLines = [...logLines, line];
    notify();
  }
}
