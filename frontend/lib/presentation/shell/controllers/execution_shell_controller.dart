import 'dart:async';

import '../../../core/gateway/execution_stream_client.dart';
import '../../../core/gateway/transport_gateway.dart';
import 'shell_controller.dart';

class ExecutionShellController {
  ExecutionShellController({
    required this.gateway,
    required this.notify,
    required this.isMounted,
    required this.appendLog,
    required this.onRunFinished,
    required this.workspace,
    required this.backendConnected,
  });

  final TransportGateway gateway;
  final ShellNotify notify;
  final ShellMounted isMounted;
  final void Function(String line) appendLog;
  final Future<void> Function() onRunFinished;
  final WorkspaceInfo? Function() workspace;
  final bool Function() backendConnected;

  List<String> executionLines = [];
  List<ExecutionInfo> executionHistory = [];
  ExecutionStatus executionStatus = ExecutionStatus.idle;
  ExecutionInfo? currentExecution;
  bool loadingHistory = false;
  List<ExecutionInfo> reportRuns = [];
  ExecutionInfo? selectedReport;
  DashboardSummary? reportsDashboard;
  bool loadingReports = false;
  bool loadingDashboard = false;
  List<RunTestFailureInfo> failedTests = [];
  bool loadingFailures = false;
  String? failedTestsRunId;

  Timer? elapsedTimer;
  Duration elapsed = Duration.zero;
  ExecutionStreamClient? streamClient;
  StreamSubscription<ExecutionStreamEvent>? streamSub;

  String get elapsedLabel {
    final seconds = elapsed.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  void dispose() {
    streamSub?.cancel();
    elapsedTimer?.cancel();
    streamClient?.disconnect();
  }

  Future<void> connectStream() async {
    await streamSub?.cancel();
    streamSub = null;
    await streamClient?.disconnect();

    final client = ExecutionStreamClient();
    streamClient = client;
    try {
      await client.connect();
      streamSub = client.events.listen(
        handleStreamEvent,
        onError: (Object error) {
          appendLog('[warn] Execution stream error: $error');
        },
      );
    } catch (error) {
      appendLog('[warn] Execution stream unavailable: $error');
    }
  }

  Future<void> disconnectStream() async {
    await streamSub?.cancel();
    streamSub = null;
    await streamClient?.disconnect();
    streamClient = null;
  }

  bool _isEventForCurrentRun(ExecutionStreamEvent event) {
    final current = currentExecution;
    if (current == null) return false;
    final runId = event.runId;
    if (runId == null || runId.isEmpty) return true;
    return runId == current.id;
  }

  void handleStreamEvent(ExecutionStreamEvent event) {
    if (!isMounted()) return;

    switch (event.type) {
      case 'output':
        // Ignore replay/noise until this session has started a run.
        if (!_isEventForCurrentRun(event)) return;
        final line = event.line;
        if (line == null) return;
        executionLines = [...executionLines, line];
        notify();
        return;
      case 'status':
        // Do not adopt historical run status on stream connect (cold start).
        if (!_isEventForCurrentRun(event)) return;
        final status = event.status;
        if (status == null) return;
        executionStatus = ExecutionStatus.fromApi(status);
        currentExecution = ExecutionInfo(
          id: currentExecution!.id,
          workspaceId: currentExecution!.workspaceId,
          projectId: currentExecution!.projectId,
          environmentId: currentExecution!.environmentId,
          projectName: currentExecution!.projectName,
          suite: currentExecution!.suite,
          status: executionStatus,
          startedAt: currentExecution!.startedAt,
          finishedAt: currentExecution!.finishedAt,
          durationMs: currentExecution!.durationMs,
          exitCode: event.exitCode ?? currentExecution!.exitCode,
          command: currentExecution!.command,
          outputDir: currentExecution!.outputDir,
          outputXml: currentExecution!.outputXml,
          logHtml: currentExecution!.logHtml,
          reportHtml: currentExecution!.reportHtml,
        );
        notify();
        return;
      case 'finished':
      case 'failed':
      case 'cancelled':
        if (!_isEventForCurrentRun(event)) return;
        executionStatus = ExecutionStatus.fromApi(event.type);
        currentExecution = ExecutionInfo(
          id: currentExecution!.id,
          workspaceId: currentExecution!.workspaceId,
          projectId: currentExecution!.projectId,
          environmentId: currentExecution!.environmentId,
          projectName: currentExecution!.projectName,
          suite: currentExecution!.suite,
          status: executionStatus,
          startedAt: currentExecution!.startedAt,
          finishedAt: currentExecution!.finishedAt,
          durationMs: currentExecution!.durationMs,
          exitCode: event.exitCode ?? currentExecution!.exitCode,
          command: currentExecution!.command,
          outputDir: currentExecution!.outputDir,
          outputXml: currentExecution!.outputXml,
          logHtml: currentExecution!.logHtml,
          reportHtml: currentExecution!.reportHtml,
        );
        stopElapsedTimer();
        notify();
        unawaited(onRunFinished());
        return;
    }
  }

  void startElapsedTimer() {
    elapsedTimer?.cancel();
    elapsed = Duration.zero;
    elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!isMounted()) return;
      elapsed += const Duration(milliseconds: 100);
      notify();
    });
  }

  void stopElapsedTimer() {
    elapsedTimer?.cancel();
    elapsedTimer = null;
  }

  Future<void> loadExecutionHistory() async {
    if (workspace() == null || !backendConnected()) {
      executionHistory = [];
      loadingHistory = false;
      notify();
      return;
    }

    loadingHistory = true;
    notify();
    try {
      executionHistory = await gateway.listExecutionHistory();
      if (!isMounted()) return;
      loadingHistory = false;
      notify();
      await loadReports();
    } catch (error) {
      if (!isMounted()) return;
      loadingHistory = false;
      notify();
      appendLog('[warn] Could not load execution history: $error');
    }
  }

  Future<void> loadReports() async {
    if (workspace() == null || !backendConnected()) {
      reportRuns = [];
      reportsDashboard = null;
      loadingReports = false;
      loadingDashboard = false;
      selectedReport = null;
      notify();
      return;
    }

    loadingReports = true;
    loadingDashboard = true;
    notify();
    try {
      final results = await Future.wait([
        gateway.listReports(),
        gateway.getReportsDashboard(),
      ]);
      if (!isMounted()) return;
      final runs = results[0] as List<ExecutionInfo>;
      final dashboard = results[1] as DashboardSummary;
      reportRuns = runs;
      reportsDashboard = dashboard;
      loadingReports = false;
      loadingDashboard = false;
      if (selectedReport != null) {
        final match =
            runs.where((item) => item.id == selectedReport!.id).toList();
        selectedReport = match.isEmpty ? null : match.first;
      }
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingReports = false;
      loadingDashboard = false;
      notify();
      appendLog('[warn] Could not load reports: $error');
    }
  }

  void resetForWorkspaceChange() {
    executionLines = [];
    executionHistory = [];
    executionStatus = ExecutionStatus.idle;
    currentExecution = null;
    reportRuns = [];
    selectedReport = null;
    reportsDashboard = null;
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
    stopElapsedTimer();
  }

  void clearFailedTests() {
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
    notify();
  }

  void prepareNewRun() {
    executionLines = [];
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
  }

  Future<void> loadFailedTests(String runId) async {
    loadingFailures = true;
    failedTestsRunId = runId;
    notify();
    try {
      // Linking runs async after index — brief retry if xml just landed.
      RunFailuresInfo? result;
      for (var attempt = 0; attempt < 4; attempt++) {
        result = await gateway.getRunFailures(runId);
        if (result.items.isNotEmpty || attempt == 3) break;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        if (!isMounted() || failedTestsRunId != runId) return;
      }
      if (!isMounted() || failedTestsRunId != runId) return;
      failedTests = result?.items ?? const [];
      loadingFailures = false;
      notify();
    } catch (error) {
      if (!isMounted() || failedTestsRunId != runId) return;
      failedTests = [];
      loadingFailures = false;
      notify();
      appendLog('[warn] Could not load failed tests: $error');
    }
  }
}
