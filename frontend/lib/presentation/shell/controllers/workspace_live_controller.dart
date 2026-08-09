import 'dart:async';
import 'dart:io';

import '../../../core/gateway/models/workspace_event_info.dart';
import '../../../core/gateway/workspace_event_stream_client.dart';
import 'shell_controller.dart';

/// Dispatches `/api/v1/workspace/events` into shell refresh hooks.
///
/// Debounces Git / explorer / test refreshes so large FS bursts stay responsive.
class WorkspaceLiveController {
  WorkspaceLiveController({
    required this.notify,
    required this.isMounted,
    required this.appendLog,
    required this.onFilesystemEvent,
    required this.onGitChanged,
    required this.onIndexUpdated,
    required this.onTestsChanged,
    required this.onEnvironmentChanged,
    required this.onProjectMissing,
    required this.onWorkspaceMissing,
    required this.onStatusMessage,
    this.onProgressBusy,
  });

  final ShellNotify notify;
  final ShellMounted isMounted;
  final void Function(String line) appendLog;
  final Future<void> Function(WorkspaceStreamEvent event) onFilesystemEvent;
  final Future<void> Function() onGitChanged;
  final Future<void> Function(WorkspaceStreamEvent event) onIndexUpdated;
  final Future<void> Function() onTestsChanged;
  final Future<void> Function() onEnvironmentChanged;
  final Future<void> Function(WorkspaceStreamEvent event) onProjectMissing;
  final Future<void> Function(WorkspaceStreamEvent event) onWorkspaceMissing;
  final void Function(String message) onStatusMessage;

  /// When true, shell may show a non-blocking progress overlay.
  final void Function(bool busy)? onProgressBusy;

  WorkspaceEventStreamClient? _client;
  StreamSubscription<WorkspaceStreamEvent>? _sub;

  Timer? _gitDebounce;
  Timer? _explorerDebounce;
  Timer? _testsDebounce;
  Timer? _statusClear;

  final List<WorkspaceStreamEvent> _pendingFs = [];
  int _externalChangeCount = 0;
  bool _indexBusyHint = false;

  Future<void> connect() async {
    await disconnect();
    final client = WorkspaceEventStreamClient();
    _client = client;
    try {
      await client.connect();
      _sub = client.events.listen(
        handleEvent,
        onError: (Object error) {
          appendLog('[warn] Workspace event stream error: $error');
        },
      );
    } catch (error) {
      appendLog('[warn] Workspace event stream unavailable: $error');
    }
  }

  Future<void> disconnect() async {
    _gitDebounce?.cancel();
    _explorerDebounce?.cancel();
    _testsDebounce?.cancel();
    _statusClear?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _client?.disconnect();
    _client = null;
    _pendingFs.clear();
  }

  void dispose() {
    unawaited(disconnect());
  }

  void handleEvent(WorkspaceStreamEvent event) {
    if (!isMounted()) return;
    if (event.type == 'connected') return;

    switch (event.type) {
      case 'FILE_CREATED':
      case 'FILE_DELETED':
      case 'FILE_MODIFIED':
      case 'FILE_RENAMED':
      case 'DIRECTORY_CREATED':
      case 'DIRECTORY_DELETED':
      case 'DIRECTORY_RENAMED':
        if (_isRunArtifactNoise(event)) return;
        _pendingFs.add(event);
        _externalChangeCount += 1;
        _scheduleExplorerFlush();
        // Skip git refresh storms from non-source churn; Save/write still
        // triggers RepositoryUpdated when needed.
        if (!_isLikelySourcePath(event)) {
          return;
        }
        _scheduleGitFlush();
        if (event.isRobotSource) {
          _scheduleTestsFlush();
        }
        return;
      case 'GIT_CHANGED':
        _scheduleGitFlush();
        return;
      case 'INDEX_PROGRESS':
        onStatusMessage(_formatProgress('Indexing', event));
        _setBusy(true);
        return;
      case 'ANALYSIS_PROGRESS':
        onStatusMessage(_formatProgress('Analyzing', event));
        _setBusy(true);
        return;
      case 'INDEX_UPDATED':
        _setBusy(false);
        onStatusMessage('Workspace synchronized');
        _scheduleStatusClear();
        unawaited(onIndexUpdated(event));
        _scheduleTestsFlush();
        return;
      case 'ENVIRONMENT_CHANGED':
        unawaited(onEnvironmentChanged());
        return;
      case 'PROJECT_CHANGED':
        if (event.reason == 'missing') {
          onStatusMessage('Project removed');
          unawaited(onProjectMissing(event));
        }
        return;
      case 'WORKSPACE_CHANGED':
        if (event.reason == 'missing') {
          onStatusMessage('Workspace removed');
          unawaited(onWorkspaceMissing(event));
        }
        // Do not set "Indexing…" on opened — INDEX_PROGRESS / INDEX_UPDATED
        // own that. A late WORKSPACE_CHANGED after INDEX_UPDATED left the
        // status bar stuck on "Indexing workspace..." for minutes.
        return;
      default:
        return;
    }
  }

  void _setBusy(bool busy) {
    _indexBusyHint = busy;
    onProgressBusy?.call(busy);
  }

  String _formatProgress(String verb, WorkspaceStreamEvent event) {
    final custom = event.message?.trim();
    final current = event.current;
    final total = event.total;
    if (custom != null && custom.isNotEmpty) {
      // Backend often embeds "N/M" already — don't append it again.
      if (current != null &&
          total != null &&
          total > 0 &&
          !RegExp(r'\d+\s*/\s*\d+').hasMatch(custom)) {
        return '$custom ($current/$total)';
      }
      return custom;
    }
    if (current != null && total != null && total > 0) {
      return '$verb… $current/$total';
    }
    return '$verb…';
  }

  void _scheduleExplorerFlush() {
    _explorerDebounce?.cancel();
    _explorerDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_flushExplorer());
    });
  }

  Future<void> _flushExplorer() async {
    if (!isMounted()) return;
    final batch = List<WorkspaceStreamEvent>.from(_pendingFs);
    _pendingFs.clear();
    if (batch.isEmpty) return;

    final byKey = <String, WorkspaceStreamEvent>{};
    for (final event in batch) {
      final key = event.absolutePath ?? event.path ?? event.type;
      byKey[key] = event;
    }
    for (final event in byKey.values) {
      await onFilesystemEvent(event);
    }
    if (_externalChangeCount > 0) {
      final count = _externalChangeCount;
      _externalChangeCount = 0;
      if (!_indexBusyHint) {
        onStatusMessage(
          count == 1
              ? '1 file changed externally'
              : '$count files changed externally',
        );
        _scheduleStatusClear();
      }
    }
  }

  void _scheduleGitFlush() {
    _gitDebounce?.cancel();
    _gitDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(onGitChanged());
    });
  }

  void _scheduleTestsFlush() {
    _testsDebounce?.cancel();
    _testsDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(onTestsChanged());
    });
  }

  void _scheduleStatusClear() {
    _statusClear?.cancel();
    _statusClear = Timer(const Duration(seconds: 4), () {
      if (!isMounted()) return;
      onStatusMessage('');
    });
  }

  static bool pathsEqual(String a, String b) {
    final left = a.replaceAll('\\', '/');
    final right = b.replaceAll('\\', '/');
    if (left == right) return true;
    try {
      return File(a).absolute.path == File(b).absolute.path;
    } catch (_) {
      return false;
    }
  }

  static bool _isRunArtifactNoise(WorkspaceStreamEvent event) {
    final paths = <String?>[
      event.absolutePath,
      event.path,
      event.oldAbsolutePath,
      event.oldPath,
    ];
    for (final path in paths) {
      if (path == null || path.isEmpty) continue;
      final normalized = path.replaceAll('\\', '/').toLowerCase();
      if (normalized.contains('/.robotstudio/reports/')) return true;
      final name = normalized.split('/').last;
      if (name == 'output.xml' ||
          name == 'log.html' ||
          name == 'report.html' ||
          name == 'xunit.xml') {
        return true;
      }
    }
    return false;
  }

  static bool _isLikelySourcePath(WorkspaceStreamEvent event) {
    if (event.isRobotSource) return true;
    final path = (event.absolutePath ?? event.path ?? '')
        .replaceAll('\\', '/')
        .toLowerCase();
    if (path.isEmpty) return false;
    return path.endsWith('.robot') ||
        path.endsWith('.resource') ||
        path.endsWith('.py') ||
        path.endsWith('.yaml') ||
        path.endsWith('.yml') ||
        path.endsWith('.txt') ||
        path.endsWith('.md');
  }
}
