import 'dart:async';

import '../../../core/gateway/transport_gateway.dart';
import '../../../core/logging/app_logger.dart';
import 'shell_controller.dart';

class WorkspaceShellController {
  WorkspaceShellController({
    required this.gateway,
    required this.notify,
    required this.isMounted,
    required this.appendLog,
    this.healthOfflineInterval = const Duration(seconds: 2),
    this.healthConnectedInterval = const Duration(seconds: 15),
    this.offlineFailureThreshold = 3,
  });

  final TransportGateway gateway;
  final ShellNotify notify;
  final ShellMounted isMounted;
  final void Function(String line) appendLog;
  final Duration healthOfflineInterval;
  final Duration healthConnectedInterval;

  /// Consecutive failed probes required before flipping connected → offline.
  /// A single blip (restart, brief socket close) should not thrash the UI.
  final int offlineFailureThreshold;

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

  Timer? _healthPollTimer;
  Future<void> Function()? _onBackendConnected;
  Future<void> Function()? _onBackendDisconnected;
  bool _probingHealth = false;
  bool _loggedOffline = false;
  bool _monitoring = false;
  int _consecutiveFailures = 0;

  EnvironmentInfo? get activeEnvironment {
    for (final environment in environments) {
      if (environment.active) return environment;
    }
    return null;
  }

  bool get backendConnected => backendStatus == 'connected';

  Duration get _nextHealthInterval =>
      backendConnected ? healthConnectedInterval : healthOfflineInterval;

  /// Probe immediately and keep polling so the shell recovers when the
  /// backend comes back. Connection state is not shown in the chrome.
  Future<void> startBackendMonitoring({
    required Future<void> Function() onConnected,
    Future<void> Function()? onDisconnected,
  }) async {
    _onBackendConnected = onConnected;
    _onBackendDisconnected = onDisconnected;
    _loggedOffline = false;
    _consecutiveFailures = 0;
    stopBackendMonitoring();
    _monitoring = true;
    backendStatus = 'connecting';
    notify();
    await _probeBackend();
    if (!isMounted() || !_monitoring) return;
    _scheduleNextHealthProbe();
  }

  void stopBackendMonitoring() {
    _monitoring = false;
    _healthPollTimer?.cancel();
    _healthPollTimer = null;
  }

  void dispose() {
    stopBackendMonitoring();
  }

  void _scheduleNextHealthProbe() {
    _healthPollTimer?.cancel();
    if (!_monitoring || !isMounted()) return;
    _healthPollTimer = Timer(_nextHealthInterval, () {
      unawaited(_probeBackend().whenComplete(_scheduleNextHealthProbe));
    });
  }

  Future<void> _probeBackend() async {
    if (!isMounted() || _probingHealth) return;
    _probingHealth = true;
    final wasConnected = backendConnected;
    try {
      final health = await gateway.health();
      if (!isMounted()) return;
      _consecutiveFailures = 0;
      _loggedOffline = false;
      if (wasConnected) {
        backendVersion = health.version;
        return;
      }
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
      AppLogger.info(
        'Backend connected',
        tag: 'Shell',
        data: 'v${health.version} modules=${health.modules.join(',')}',
      );
      final onConnected = _onBackendConnected;
      if (onConnected != null) {
        await onConnected();
      }
    } catch (error, stackTrace) {
      if (!isMounted()) return;
      _consecutiveFailures++;
      if (wasConnected) {
        if (_consecutiveFailures < offlineFailureThreshold) {
          AppLogger.debug(
            'Health probe failed '
            '($_consecutiveFailures/$offlineFailureThreshold) — ignoring',
            tag: 'Shell',
            data: '$error',
          );
          return;
        }
        AppLogger.error(
          'Backend lost — retrying',
          tag: 'Shell',
          error: error,
          stackTrace: stackTrace,
        );
        backendStatus = 'offline';
        backendVersion = null;
        _loggedOffline = true;
        logLines = [
          ...logLines,
          '[error] Backend connection lost: $error',
          '[info] Waiting for backend…',
        ];
        notify();
        final onDisconnected = _onBackendDisconnected;
        if (onDisconnected != null) {
          await onDisconnected();
        }
        return;
      }
      if (!_loggedOffline) {
        _loggedOffline = true;
        AppLogger.error(
          'Backend unavailable — retrying',
          tag: 'Shell',
          error: error,
          stackTrace: stackTrace,
        );
        backendStatus = 'offline';
        logLines = [
          '[error] Backend unavailable: $error',
          '[info] Waiting for backend… start with: python -m robot_studio.main',
        ];
        notify();
      } else if (backendStatus != 'offline') {
        backendStatus = 'offline';
        notify();
      }
    } finally {
      _probingHealth = false;
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
