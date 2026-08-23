import 'dart:async';

import '../../../core/gateway/execution_stream_client.dart';
import '../../../core/gateway/transport_gateway.dart';
import '../../execution/live_progress_markers.dart';
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

  /// Failures for the Reports selection (kept separate from live Execution).
  List<RunTestFailureInfo> reportFailedTests = [];
  bool loadingReportFailures = false;
  String? reportFailedTestsRunId;

  /// True after a report failures fetch finished for [reportFailedTestsRunId].
  /// While false, Reports hides the Failed Tests block (no empty/skeleton flash).
  bool reportFailuresReady = false;

  final Map<String, List<RunTestFailureInfo>> _reportFailuresCache = {};
  Timer? _reportFailuresSkeletonTimer;
  Timer? _liveFailuresSkeletonTimer;

  static const _reportSkeletonDelay = Duration(milliseconds: 350);

  Timer? elapsedTimer;
  Duration elapsed = Duration.zero;
  ExecutionStreamClient? streamClient;
  StreamSubscription<ExecutionStreamEvent>? streamSub;
  Timer? _statusReconcileTimer;
  bool _reconcilingStatus = false;

  /// Cap console memory; 10k-test runs can emit huge stdout.
  static const int maxExecutionLines = 4000;

  Timer? _outputFlushTimer;
  final List<String> _pendingOutput = [];
  bool _outputDropped = false;

  /// RIDE-style "now running" (suite / test / keyword).
  String liveSuite = '';
  String liveTest = '';
  String liveKeyword = '';

  String get elapsedLabel {
    final seconds = elapsed.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  void dispose() {
    streamSub?.cancel();
    elapsedTimer?.cancel();
    _statusReconcileTimer?.cancel();
    _outputFlushTimer?.cancel();
    _reportFailuresSkeletonTimer?.cancel();
    _liveFailuresSkeletonTimer?.cancel();
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
        final line = event.line;
        if (line == null) return;
        // Allow lines before HTTP assigns currentExecution (run already started).
        if (currentExecution != null && !_isEventForCurrentRun(event)) return;
        final kept = _consumeProgressMarker(line);
        if (kept == null) return;
        // Skip blank leftovers from stripped progress markers.
        if (kept.trim().isEmpty) return;
        _pendingOutput.add(kept);
        _scheduleOutputFlush();
        return;
      case 'status':
        // Do not adopt historical run status on stream connect (cold start).
        if (currentExecution == null) return;
        if (!_isEventForCurrentRun(event)) return;
        final status = event.status;
        if (status == null) return;
        final parsed = ExecutionStatus.fromApi(status);
        if (!parsed.isActive) {
          // Reconnect snapshot can arrive as type=status with a terminal
          // value — treat it like finished/failed so the timer stops.
          _applyTerminalRun(status: parsed, exitCode: event.exitCode);
          return;
        }
        executionStatus = parsed;
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
      case 'aborted':
      case 'finished':
      case 'failed':
      case 'cancelled':
        if (!_isEventForCurrentRun(event)) return;
        _applyTerminalRun(
          status: ExecutionStatus.fromApi(event.type),
          exitCode: event.exitCode,
        );
        return;
    }
  }

  void _applyTerminalRun({
    required ExecutionStatus status,
    int? exitCode,
    ExecutionInfo? run,
  }) {
    if (!executionStatus.isActive) return;
    _flushOutputNow();
    _clearLiveProgress();
    executionStatus = status;
    final base = run ?? currentExecution;
    if (base != null) {
      currentExecution = ExecutionInfo(
        id: base.id,
        workspaceId: base.workspaceId,
        projectId: base.projectId,
        environmentId: base.environmentId,
        projectName: base.projectName,
        suite: base.suite,
        status: status,
        startedAt: base.startedAt,
        finishedAt: base.finishedAt ?? run?.finishedAt,
        durationMs: base.durationMs ?? run?.durationMs,
        exitCode: exitCode ?? run?.exitCode ?? base.exitCode,
        command: base.command,
        outputDir: base.outputDir ?? run?.outputDir,
        outputXml: base.outputXml ?? run?.outputXml,
        logHtml: base.logHtml ?? run?.logHtml,
        reportHtml: base.reportHtml ?? run?.reportHtml,
      );
    }
    stopElapsedTimer();
    notify();
    unawaited(onRunFinished());
  }

  /// Apply any progress marker and return console text to keep.
  /// Returns null when the line was marker-only (drop from Live Output).
  String? _consumeProgressMarker(String line) {
    final parsed = parseProgressMarker(line);
    if (parsed == null) return line;
    _updateLiveProgress(parsed.suite, parsed.test, parsed.keyword);
    return parsed.consoleLine;
  }

  void _updateLiveProgress(String suite, String test, String keyword) {
    if (suite == liveSuite && test == liveTest && keyword == liveKeyword) {
      return;
    }
    liveSuite = suite;
    liveTest = test;
    liveKeyword = keyword;
    notify();
  }

  void _clearLiveProgress() {
    liveSuite = '';
    liveTest = '';
    liveKeyword = '';
  }

  void _scheduleOutputFlush() {
    if (_outputFlushTimer?.isActive ?? false) return;
    _outputFlushTimer = Timer(
      const Duration(milliseconds: 100),
      _flushOutputNow,
    );
  }

  void _flushOutputNow() {
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    if (_pendingOutput.isEmpty) return;
    final batch = List<String>.from(_pendingOutput);
    _pendingOutput.clear();

    final next = List<String>.from(executionLines)..addAll(batch);
    if (next.length > maxExecutionLines) {
      final overflow = next.length - maxExecutionLines;
      executionLines = next.sublist(overflow);
      if (!_outputDropped) {
        _outputDropped = true;
        executionLines = [
          '[info] Console trimmed — keeping last $maxExecutionLines lines',
          ...executionLines,
        ];
      }
    } else {
      executionLines = next;
    }
    notify();
  }

  void clearExecutionLines() {
    executionLines = [];
    _pendingOutput.clear();
    _outputDropped = false;
    notify();
  }

  void startElapsedTimer() {
    elapsedTimer?.cancel();
    elapsed = Duration.zero;
    // 100ms rebuilds of the whole shell starve input during huge runs.
    elapsedTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!isMounted()) return;
      elapsed += const Duration(milliseconds: 250);
      notify();
    });
    _startStatusReconcile();
  }

  void stopElapsedTimer() {
    elapsedTimer?.cancel();
    elapsedTimer = null;
    _stopStatusReconcile();
  }

  void _startStatusReconcile() {
    _statusReconcileTimer?.cancel();
    // Large runs can drop the WebSocket ``finished`` frame under output
    // backpressure; poll HTTP so Running/Stop cannot stick forever.
    _statusReconcileTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_reconcileActiveRunStatus());
    });
  }

  void _stopStatusReconcile() {
    _statusReconcileTimer?.cancel();
    _statusReconcileTimer = null;
  }

  Future<void> _reconcileActiveRunStatus() async {
    if (!isMounted() || !executionStatus.isActive || _reconcilingStatus) {
      return;
    }
    final expectedId = currentExecution?.id;
    _reconcilingStatus = true;
    try {
      final info = await gateway.getExecutionStatus();
      if (!isMounted() || !executionStatus.isActive) return;
      if (expectedId != null &&
          info.run != null &&
          info.run!.id != expectedId) {
        return;
      }
      if (info.status.isActive) return;
      final terminal = info.status == ExecutionStatus.idle
          ? ExecutionStatus.finished
          : info.status;
      _applyTerminalRun(
        status: terminal,
        exitCode: info.run?.exitCode,
        run: info.run,
      );
    } catch (error) {
      appendLog('[warn] Could not reconcile execution status: $error');
    } finally {
      _reconcilingStatus = false;
    }
  }

  /// Test seam for [_reconcileActiveRunStatus].
  Future<void> reconcileActiveRunStatusForTest() => _reconcileActiveRunStatus();

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
      reportFailedTests = [];
      loadingReportFailures = false;
      reportFailedTestsRunId = null;
      reportFailuresReady = false;
      _reportFailuresCache.clear();
      _reportFailuresSkeletonTimer?.cancel();
      _reportFailuresSkeletonTimer = null;
      notify();
      return;
    }

    final hasCachedRuns = reportRuns.isNotEmpty || selectedReport != null;
    if (!hasCachedRuns) {
      loadingReports = true;
    }
    loadingDashboard = reportsDashboard == null;
    notify();

    final listFuture = gateway.listReports();
    final dashFuture = gateway.getReportsDashboard();

    try {
      final runs = await listFuture;
      if (!isMounted()) return;
      reportRuns = runs;
      if (selectedReport != null) {
        final match = runs
            .where((item) => item.id == selectedReport!.id)
            .toList();
        selectedReport = match.isEmpty ? null : match.first;
      }
      selectedReport ??= runs.isEmpty ? null : runs.first;
      loadingReports = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingReports = false;
      loadingDashboard = false;
      notify();
      appendLog('[warn] Could not load reports: $error');
      return;
    }

    unawaited(_applyReportsDashboard(dashFuture));
  }

  Future<void> _applyReportsDashboard(
    Future<DashboardSummary> dashFuture,
  ) async {
    try {
      final dashboard = await dashFuture;
      if (!isMounted()) return;
      reportsDashboard = dashboard;
      loadingDashboard = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingDashboard = false;
      notify();
      appendLog('[warn] Could not load reports dashboard: $error');
    }
  }

  void resetForWorkspaceChange() {
    executionLines = [];
    _pendingOutput.clear();
    _outputDropped = false;
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    _clearLiveProgress();
    executionHistory = [];
    executionStatus = ExecutionStatus.idle;
    currentExecution = null;
    reportRuns = [];
    selectedReport = null;
    reportsDashboard = null;
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
    _liveFailuresSkeletonTimer?.cancel();
    _liveFailuresSkeletonTimer = null;
    reportFailedTests = [];
    loadingReportFailures = false;
    reportFailedTestsRunId = null;
    reportFailuresReady = false;
    _reportFailuresCache.clear();
    _reportFailuresSkeletonTimer?.cancel();
    _reportFailuresSkeletonTimer = null;
    stopElapsedTimer();
  }

  void clearFailedTests() {
    _liveFailuresSkeletonTimer?.cancel();
    _liveFailuresSkeletonTimer = null;
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
    notify();
  }

  void clearReportFailedTests() {
    _reportFailuresSkeletonTimer?.cancel();
    _reportFailuresSkeletonTimer = null;
    reportFailedTests = [];
    loadingReportFailures = false;
    reportFailedTestsRunId = null;
    reportFailuresReady = false;
    notify();
  }

  void prepareNewRun() {
    executionLines = [];
    _pendingOutput.clear();
    _outputDropped = false;
    _outputFlushTimer?.cancel();
    _outputFlushTimer = null;
    failedTests = [];
    loadingFailures = false;
    failedTestsRunId = null;
    _liveFailuresSkeletonTimer?.cancel();
    _liveFailuresSkeletonTimer = null;
    _clearLiveProgress();
    // Clear so early stream lines for the new run are not filtered by the
    // previous run id while the start HTTP call is still in flight.
    currentExecution = null;
    executionStatus = ExecutionStatus.running;
  }

  Future<void> loadFailedTests(String runId) async {
    await _loadFailedTestsFor(
      runId,
      setLoading: (value) => loadingFailures = value,
      setRunId: (value) => failedTestsRunId = value,
      currentRunId: () => failedTestsRunId,
      setItems: (items) => failedTests = items,
    );
  }

  Future<void> loadReportFailedTests(String runId) async {
    _reportFailuresSkeletonTimer?.cancel();
    _reportFailuresSkeletonTimer = null;

    final cached = _reportFailuresCache[runId];
    if (cached != null) {
      reportFailedTests = cached;
      reportFailedTestsRunId = runId;
      loadingReportFailures = false;
      reportFailuresReady = true;
      notify();
      return;
    }

    // Quiet load: hide the section until data arrives (or skeleton delay).
    reportFailedTests = [];
    reportFailedTestsRunId = runId;
    loadingReportFailures = false;
    reportFailuresReady = false;
    notify();

    _reportFailuresSkeletonTimer = Timer(_reportSkeletonDelay, () {
      if (!isMounted() || reportFailedTestsRunId != runId) return;
      if (reportFailuresReady || reportFailedTests.isNotEmpty) return;
      loadingReportFailures = true;
      notify();
    });

    try {
      // Historical reports already have output.xml — no retry backoff.
      final result = await gateway.getRunFailures(runId);
      if (!isMounted() || reportFailedTestsRunId != runId) return;
      _reportFailuresSkeletonTimer?.cancel();
      _reportFailuresSkeletonTimer = null;
      final items = result.items;
      reportFailedTests = items;
      _reportFailuresCache[runId] = items;
      loadingReportFailures = false;
      reportFailuresReady = true;
      notify();
    } catch (error) {
      if (!isMounted() || reportFailedTestsRunId != runId) return;
      _reportFailuresSkeletonTimer?.cancel();
      _reportFailuresSkeletonTimer = null;
      reportFailedTests = [];
      loadingReportFailures = false;
      reportFailuresReady = true;
      notify();
      appendLog('[warn] Could not load failed tests: $error');
    }
  }

  Future<void> _loadFailedTestsFor(
    String runId, {
    required void Function(bool value) setLoading,
    required void Function(String? value) setRunId,
    required String? Function() currentRunId,
    required void Function(List<RunTestFailureInfo> items) setItems,
  }) async {
    _liveFailuresSkeletonTimer?.cancel();
    setLoading(false);
    setRunId(runId);
    setItems(const []);
    notify();
    _liveFailuresSkeletonTimer = Timer(_reportSkeletonDelay, () {
      if (!isMounted() || currentRunId() != runId) return;
      setLoading(true);
      notify();
    });
    try {
      // Linking runs async after index — brief retry if xml just landed.
      RunFailuresInfo? result;
      for (var attempt = 0; attempt < 4; attempt++) {
        result = await gateway.getRunFailures(runId);
        if (result.items.isNotEmpty || attempt == 3) break;
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        if (!isMounted() || currentRunId() != runId) return;
      }
      if (!isMounted() || currentRunId() != runId) return;
      _liveFailuresSkeletonTimer?.cancel();
      _liveFailuresSkeletonTimer = null;
      setItems(result?.items ?? const []);
      setLoading(false);
      notify();
    } catch (error) {
      if (!isMounted() || currentRunId() != runId) return;
      _liveFailuresSkeletonTimer?.cancel();
      _liveFailuresSkeletonTimer = null;
      setItems(const []);
      setLoading(false);
      notify();
      appendLog('[warn] Could not load failed tests: $error');
    }
  }
}
