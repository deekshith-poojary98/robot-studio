import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gateway/execution_stream_client.dart';
import '../../core/gateway/rest_transport_gateway.dart';
import '../../core/gateway/transport_gateway.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../environment/clone_environment_dialog.dart';
import '../environment/create_environment_dialog.dart';
import '../environment/delete_environment_dialog.dart';
import '../environment/environment_details_panel.dart';
import '../environment/environment_manager_page.dart';
import '../environment/import_environment_dialog.dart';
import '../editor/editor_page.dart';
import '../execution/execution_page.dart';
import '../packages/package_details_panel.dart';
import '../packages/package_manager_page.dart';
import '../packages/package_progress_dialog.dart';
import '../packages/search_packages_dialog.dart';
import '../packages/uninstall_package_dialog.dart';
import '../panels/bottom_panel.dart';
import '../panels/side_panel.dart';
import '../project/import_project_dialog.dart';
import '../project/new_project_dialog.dart';
import '../project/project_details_panel.dart';
import '../reports/delete_run_dialog.dart';
import '../reports/reports_page.dart';
import '../search/search_page.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/sidebar_panel.dart';
import '../toolbar/app_toolbar.dart';
import '../workspace/new_workspace_dialog.dart';
import '../workspace/welcome_screen.dart';
import 'status_bar.dart';

enum _CenterView {
  welcome,
  placeholder,
  project,
  environment,
  manager,
  packages,
  packageDetail,
  execution,
  reports,
  search,
  editor,
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    TransportGateway? gateway,
    TransportGateway? apiClient,
  }) : _gateway = gateway ?? apiClient;

  /// Supports both [gateway] and legacy [apiClient] parameter names.
  final TransportGateway? _gateway;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  SidebarPanel _activePanel = SidebarPanel.explorer;
  String _backendStatus = 'connecting';
  String? _backendVersion;
  List<String> _logLines = [];

  WorkspaceInfo? _activeWorkspace;
  ProjectInfo? _selectedProject;
  EnvironmentInfo? _selectedEnvironment;
  List<ProjectInfo> _projects = [];
  List<EnvironmentInfo> _environments = [];
  List<WorkspaceInfo> _recentWorkspaces = [];
  List<ProjectInfo> _recentProjects = [];
  EnvironmentSort _environmentSort = EnvironmentSort.active;
  bool _showEnvironmentManager = false;
  bool _showPackageManager = false;
  PackageInfo? _selectedPackage;
  List<PackageInfo> _packages = [];
  PackageSort _packageSort = PackageSort.name;
  String _packageQuery = '';
  bool _robotFrameworkInstalled = false;
  String? _robotFrameworkVersion;
  bool _loadingRecent = true;
  bool _loadingProjects = false;
  bool _loadingEnvironments = false;
  bool _loadingPackages = false;
  bool _busy = false;

  List<String> _executionLines = [];
  List<ExecutionInfo> _executionHistory = [];
  ExecutionStatus _executionStatus = ExecutionStatus.idle;
  ExecutionInfo? _currentExecution;
  bool _loadingHistory = false;
  bool _showExecutionPage = false;
  List<ExecutionInfo> _reportRuns = [];
  ExecutionInfo? _selectedReport;
  DashboardSummary? _reportsDashboard;
  bool _loadingReports = false;
  bool _loadingDashboard = false;
  bool _showReportsPage = false;
  String _searchQuery = '';
  SymbolKind? _searchKind;
  List<IndexedSymbolInfo> _searchResults = [];
  bool _isSearching = false;
  IndexedSymbolInfo? _selectedSymbol;
  HoverInfo? _hoverInfo;
  List<SymbolReferenceInfo> _references = [];
  bool _isLoadingLanguage = false;
  String? _navigationMessage;
  IndexStatusInfo? _indexStatus;
  bool _loadingIndexStatus = false;
  bool _showSearchPage = false;
  String? _selectedSuitePath;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  ExecutionStreamClient? _streamClient;
  StreamSubscription<ExecutionStreamEvent>? _streamSub;

  List<EditorTabInfo> _editorTabs = [];
  String? _activeEditorPath;
  List<IndexedSymbolInfo> _documentOutline = [];
  bool _loadingOutline = false;
  bool _wordWrap = true;
  HoverInfo? _editorHover;
  List<SymbolReferenceInfo> _editorReferences = [];
  String? _editorStatusMessage;
  int? _jumpToLine;
  int _cursorLine = 1;
  int _cursorColumn = 1;
  List<FileTreeNode> _fileTree = [];
  List<String> _recentFiles = [];
  bool _showEditorPage = false;
  IndexedSymbolInfo? _selectedOutlineSymbol;

  late final TransportGateway _gateway =
      widget._gateway ?? RestTransportGateway();

  EnvironmentInfo? get _activeEnvironment {
    for (final environment in _environments) {
      if (environment.active) return environment;
    }
    return null;
  }

  EditorTabInfo? get _activeEditorTab {
    final path = _activeEditorPath;
    if (path == null) return null;
    for (final tab in _editorTabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    AppLogger.info('AppShell init', tag: 'Shell');
    _bootstrap();
  }

  @override
  void dispose() {
    AppLogger.debug('AppShell dispose', tag: 'Shell');
    _streamSub?.cancel();
    _elapsedTimer?.cancel();
    _streamClient?.disconnect();
    super.dispose();
  }

  String get _elapsedLabel {
    final seconds = _elapsed.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  void _clearExecutionPageUnlessTests() {
    if (_activePanel != SidebarPanel.tests) {
      _showExecutionPage = false;
    }
  }

  Future<void> _bootstrap() async {
    AppLogger.debug('Bootstrap start', tag: 'Shell');
    await _checkBackend();
    await _loadRecent();
    AppLogger.debug(
      'Bootstrap done',
      tag: 'Shell',
      data: 'backend=$_backendStatus',
    );
  }

  Future<void> _checkBackend() async {
    AppLogger.debug('Checking backend health', tag: 'Shell');
    try {
      final health = await _gateway.health();
      if (!mounted) return;
      setState(() {
        _backendStatus = 'connected';
        _backendVersion = health.version;
        _logLines = [
          '[info] Connected to backend v${health.version}',
          '[info] ${health.modules.length} modules registered',
        ];
      });
      for (final line in _logLines) {
        AppLogger.fromConsoleLine(line, tag: 'Shell');
      }
      AppLogger.info(
        'Backend connected',
        tag: 'Shell',
        data: 'v${health.version} modules=${health.modules.join(',')}',
      );
      _connectExecutionStream();
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppLogger.error(
        'Backend unavailable',
        tag: 'Shell',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _backendStatus = 'offline';
        _logLines = [
          '[error] Backend unavailable: $error',
          '[info] Start the backend with: python -m robot_studio.main',
        ];
      });
    }
  }

  Future<void> _loadRecent() async {
    if (_backendStatus != 'connected') {
      setState(() {
        _loadingRecent = false;
        _recentWorkspaces = [];
        _recentProjects = [];
      });
      return;
    }

    setState(() => _loadingRecent = true);
    try {
      final workspaces = await _gateway.listRecentWorkspaces();
      final projects = await _gateway.listRecentProjects();
      if (!mounted) return;
      setState(() {
        _recentWorkspaces = workspaces;
        _recentProjects = projects;
        _loadingRecent = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRecent = false;
        _appendLog('[warn] Could not load recent items: $error');
      });
    }
  }

  Future<void> _loadProjects() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _projects = [];
        _loadingProjects = false;
      });
      return;
    }

    setState(() => _loadingProjects = true);
    try {
      final projects = await _gateway.listProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loadingProjects = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingProjects = false;
        _appendLog('[warn] Could not load projects: $error');
      });
    }
  }

  Future<void> _loadEnvironments() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _environments = [];
        _loadingEnvironments = false;
        _selectedEnvironment = null;
      });
      return;
    }

    setState(() => _loadingEnvironments = true);
    try {
      final environments = await _gateway.listEnvironments(
        sort: _environmentSort,
      );
      if (!mounted) return;
      setState(() {
        _environments = environments;
        _loadingEnvironments = false;
        if (_selectedEnvironment != null) {
          final match = environments
              .where((item) => item.id == _selectedEnvironment!.id)
              .toList();
          _selectedEnvironment = match.isEmpty ? null : match.first;
        }
      });
      await _loadPackages();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingEnvironments = false;
        _appendLog('[warn] Could not load environments: $error');
      });
    }
  }

  Future<void> _loadPackages() async {
    if (_activeWorkspace == null ||
        _backendStatus != 'connected' ||
        _activeEnvironment == null) {
      setState(() {
        _packages = [];
        _loadingPackages = false;
        _robotFrameworkInstalled = false;
        _robotFrameworkVersion = null;
        _selectedPackage = null;
      });
      return;
    }

    setState(() => _loadingPackages = true);
    try {
      final result = await _gateway.listPackages(
        query: _packageQuery.isEmpty ? null : _packageQuery,
        sort: _packageSort,
      );
      if (!mounted) return;
      setState(() {
        _packages = result.packages;
        _robotFrameworkInstalled = result.robotFrameworkInstalled;
        _robotFrameworkVersion = result.robotFrameworkVersion;
        _loadingPackages = false;
        if (_selectedPackage != null) {
          final match = result.packages
              .where((item) => item.name == _selectedPackage!.name)
              .toList();
          _selectedPackage = match.isEmpty ? null : match.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPackages = false;
        _appendLog('[warn] Could not load packages: $error');
      });
    }
  }

  void _appendLog(String line) {
    AppLogger.fromConsoleLine(line, tag: 'Shell');
    setState(() {
      _logLines = [..._logLines, line];
    });
  }

  Future<void> _connectExecutionStream() async {
    await _streamSub?.cancel();
    _streamSub = null;
    await _streamClient?.disconnect();

    final client = ExecutionStreamClient();
    _streamClient = client;
    try {
      await client.connect();
      _streamSub = client.events.listen(
        _handleStreamEvent,
        onError: (Object error) {
          _appendLog('[warn] Execution stream error: $error');
        },
      );
    } catch (error) {
      _appendLog('[warn] Execution stream unavailable: $error');
    }
  }

  void _handleStreamEvent(ExecutionStreamEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case 'output':
        final line = event.line;
        if (line == null) return;
        setState(() {
          _executionLines = [..._executionLines, line];
        });
        return;
      case 'status':
        final status = event.status;
        if (status == null) return;
        setState(() {
          _executionStatus = ExecutionStatus.fromApi(status);
          if (_currentExecution != null) {
            _currentExecution = ExecutionInfo(
              id: _currentExecution!.id,
              workspaceId: _currentExecution!.workspaceId,
              projectId: _currentExecution!.projectId,
              environmentId: _currentExecution!.environmentId,
              projectName: _currentExecution!.projectName,
              suite: _currentExecution!.suite,
              status: _executionStatus,
              startedAt: _currentExecution!.startedAt,
              finishedAt: _currentExecution!.finishedAt,
              durationMs: _currentExecution!.durationMs,
              exitCode: event.exitCode ?? _currentExecution!.exitCode,
              command: _currentExecution!.command,
              outputDir: _currentExecution!.outputDir,
              outputXml: _currentExecution!.outputXml,
              logHtml: _currentExecution!.logHtml,
              reportHtml: _currentExecution!.reportHtml,
            );
          }
        });
        return;
      case 'finished':
      case 'failed':
      case 'cancelled':
        setState(() {
          _executionStatus = ExecutionStatus.fromApi(event.type);
          if (_currentExecution != null) {
            _currentExecution = ExecutionInfo(
              id: _currentExecution!.id,
              workspaceId: _currentExecution!.workspaceId,
              projectId: _currentExecution!.projectId,
              environmentId: _currentExecution!.environmentId,
              projectName: _currentExecution!.projectName,
              suite: _currentExecution!.suite,
              status: _executionStatus,
              startedAt: _currentExecution!.startedAt,
              finishedAt: _currentExecution!.finishedAt,
              durationMs: _currentExecution!.durationMs,
              exitCode: event.exitCode ?? _currentExecution!.exitCode,
              command: _currentExecution!.command,
              outputDir: _currentExecution!.outputDir,
              outputXml: _currentExecution!.outputXml,
              logHtml: _currentExecution!.logHtml,
              reportHtml: _currentExecution!.reportHtml,
            );
          }
        });
        _stopElapsedTimer();
        _loadExecutionHistory();
        return;
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsed = Duration.zero;
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed += const Duration(milliseconds: 100);
      });
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<void> _loadExecutionHistory() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _executionHistory = [];
        _loadingHistory = false;
      });
      return;
    }

    setState(() => _loadingHistory = true);
    try {
      final history = await _gateway.listExecutionHistory();
      if (!mounted) return;
      setState(() {
        _executionHistory = history;
        _loadingHistory = false;
      });
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      _appendLog('[warn] Could not load execution history: $error');
    }
  }

  Future<void> _loadReports() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _reportRuns = [];
        _reportsDashboard = null;
        _loadingReports = false;
        _loadingDashboard = false;
        _selectedReport = null;
      });
      return;
    }

    setState(() {
      _loadingReports = true;
      _loadingDashboard = true;
    });
    try {
      final results = await Future.wait([
        _gateway.listReports(),
        _gateway.getReportsDashboard(),
      ]);
      if (!mounted) return;
      final runs = results[0] as List<ExecutionInfo>;
      final dashboard = results[1] as DashboardSummary;
      setState(() {
        _reportRuns = runs;
        _reportsDashboard = dashboard;
        _loadingReports = false;
        _loadingDashboard = false;
        if (_selectedReport != null) {
          final match =
              runs.where((item) => item.id == _selectedReport!.id).toList();
          _selectedReport = match.isEmpty ? null : match.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingReports = false;
        _loadingDashboard = false;
      });
      _appendLog('[warn] Could not load reports: $error');
    }
  }

  Future<void> _openReports() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before viewing reports.',
      );
      return;
    }
    setState(() {
      _showReportsPage = true;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.reports;
      _clearExecutionPageUnlessTests();
    });
    await _loadReports();
  }

  Future<void> _selectReport(ExecutionInfo run) async {
    setState(() {
      _selectedReport = run;
      _showReportsPage = true;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.reports;
      _clearExecutionPageUnlessTests();
    });
    try {
      final fresh = await _gateway.getReport(run.id);
      if (!mounted) return;
      setState(() => _selectedReport = fresh);
    } catch (error) {
      _appendLog('[warn] Could not refresh report details: $error');
    }
  }

  Future<void> _openReportLog() async {
    final run = _selectedReport;
    if (run == null) return;
    try {
      await _gateway.openReportLog(run.id);
    } catch (error) {
      if (!mounted) return;
      await _showError('Open log', error);
    }
  }

  Future<void> _openReportHtml() async {
    final run = _selectedReport;
    if (run == null) return;
    try {
      await _gateway.openReportHtml(run.id);
    } catch (error) {
      if (!mounted) return;
      await _showError('Open report', error);
    }
  }

  Future<void> _revealReport() async {
    final run = _selectedReport;
    if (run == null) return;
    try {
      await _gateway.revealReport(run.id);
    } catch (error) {
      if (!mounted) return;
      await _showError('Reveal report', error);
    }
  }

  Future<void> _deleteSelectedReport() async {
    final run = _selectedReport;
    if (run == null) return;
    final confirmed = await showDeleteRunDialog(context, run: run);
    if (confirmed != true) return;
    try {
      await _gateway.deleteReport(run.id);
      if (!mounted) return;
      setState(() => _selectedReport = null);
      _appendLog('[info] Deleted report "${run.projectName}"');
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      await _showError('Delete report', error);
    }
  }

  Future<void> _handleRunFile() async {
    AppLogger.info(
      'Run file requested',
      tag: 'Shell',
      data: {
        'project': _selectedProject?.name,
        'suite': _selectedSuitePath,
        'env': _activeEnvironment?.name,
      },
    );
    if (_selectedProject == null) {
      await _showError(
        'Project required',
        'Open a project before running tests.',
      );
      return;
    }
    if (_activeEnvironment == null) {
      await _showError(
        'Environment required',
        'Activate an environment before running tests.',
      );
      return;
    }

    setState(() {
      _executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();

    try {
      final run = await _gateway.runFile(file: _selectedSuitePath);
      if (!mounted) return;
      AppLogger.info(
        'Run started',
        tag: 'Shell',
        data: 'id=${run.id} status=${run.status.name}',
      );
      setState(() {
        _executionStatus = run.status;
        _currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      _appendLog('[error] Run failed: $error');
      await _showError('Execution error', error);
    }
  }

  Future<void> _handleRunProject() async {
    AppLogger.info(
      'Run project requested',
      tag: 'Shell',
      data: {
        'project': _selectedProject?.name,
        'env': _activeEnvironment?.name,
      },
    );
    if (_selectedProject == null) {
      await _showError(
        'Project required',
        'Open a project before running tests.',
      );
      return;
    }
    if (_activeEnvironment == null) {
      await _showError(
        'Environment required',
        'Activate an environment before running tests.',
      );
      return;
    }

    setState(() {
      _executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();

    try {
      final run = await _gateway.runProject();
      if (!mounted) return;
      AppLogger.info(
        'Run project started',
        tag: 'Shell',
        data: 'id=${run.id} status=${run.status.name}',
      );
      setState(() {
        _executionStatus = run.status;
        _currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      _appendLog('[error] Run failed: $error');
      await _showError('Execution error', error);
    }
  }

  Future<void> _handleStopExecution() async {
    try {
      final run = await _gateway.stopExecution();
      if (!mounted) return;
      setState(() {
        _executionStatus = run.status;
        _currentExecution = run;
      });
      _stopElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      _appendLog('[error] Stop failed: $error');
      await _showError('Stop execution error', error);
    }
  }

  Future<void> _showError(String title, Object error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNewWorkspace() async {
    final result = await showNewWorkspaceDialog(context);
    if (result == null) return;
    await _runWorkspaceAction(
      () => _gateway.createWorkspace(
        name: result.name,
        location: result.location,
      ),
      successMessage: 'Created workspace',
    );
  }

  Future<void> _handleOpenWorkspace() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Open Workspace',
    );
    if (selected == null) return;
    await _runWorkspaceAction(
      () => _gateway.openWorkspace(selected),
      successMessage: 'Opened workspace',
    );
  }

  Future<void> _handleOpenRecentWorkspace(WorkspaceInfo workspace) async {
    await _runWorkspaceAction(
      () => _gateway.openWorkspace(workspace.path),
      successMessage: 'Opened workspace',
    );
  }

  Future<void> _runWorkspaceAction(
    Future<WorkspaceInfo> Function() action, {
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workspace = await action();
      if (!mounted) return;
      setState(() {
        _activeWorkspace = workspace;
        _selectedProject = null;
        _selectedEnvironment = null;
        _selectedPackage = null;
        _showEnvironmentManager = false;
        _showPackageManager = false;
        _showReportsPage = false;
        _showSearchPage = false;
        _selectedReport = null;
        _reportRuns = [];
        _reportsDashboard = null;
        _searchQuery = '';
        _searchKind = null;
        _searchResults = [];
        _selectedSymbol = null;
        _hoverInfo = null;
        _references = [];
        _navigationMessage = null;
        _activePanel = SidebarPanel.explorer;
        _editorTabs = [];
        _activeEditorPath = null;
        _documentOutline = [];
        _editorHover = null;
        _editorReferences = [];
        _editorStatusMessage = null;
        _jumpToLine = null;
        _fileTree = [];
        _recentFiles = [];
        _showEditorPage = false;
        _selectedOutlineSymbol = null;
        _busy = false;
      });
      _appendLog('[info] $successMessage "${workspace.name}"');
      await _loadRecent();
      await _loadProjects();
      await _loadEnvironments();
      await _loadExecutionHistory();
      await _loadIndexStatus();
      await _loadFileTree();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Workspace error', error);
    }
  }

  Future<void> _handleNewProject() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before creating a project.',
      );
      return;
    }
    final result = await showNewProjectDialog(context);
    if (result == null) return;
    await _runProjectAction(
      () => _gateway.createProject(name: result.name, type: result.type),
      successMessage: 'Created project',
    );
  }

  Future<void> _handleImportProject() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before importing a project.',
      );
      return;
    }
    final path = await showImportProjectDialog(context);
    if (path == null) return;
    await _runProjectAction(
      () => _gateway.importProject(path),
      successMessage: 'Imported project',
    );
  }

  Future<void> _handleSelectProject(ProjectInfo project) async {
    await _runProjectAction(
      () => _gateway.openProject(project.id),
      successMessage: 'Opened project',
    );
  }

  Future<void> _handleOpenRecentProject(ProjectInfo project) async {
    if (_activeWorkspace == null ||
        _activeWorkspace!.id != project.workspaceId) {
      await _showError(
        'Open workspace first',
        'Open the project\'s workspace, then select the project from the explorer.',
      );
      return;
    }
    await _handleSelectProject(project);
  }

  Future<void> _runProjectAction(
    Future<ProjectInfo> Function() action, {
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final project = await action();
      if (!mounted) return;
      setState(() {
        _selectedProject = project;
        _selectedEnvironment = null;
        _selectedPackage = null;
        _showEnvironmentManager = false;
        _showPackageManager = false;
        _showEditorPage = false;
        _clearExecutionPageUnlessTests();
        _busy = false;
      });
      _appendLog('[info] $successMessage "${project.name}"');
      await _loadProjects();
      await _loadRecent();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Project error', error);
    }
  }

  Future<void> _handleManageEnvironments() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before managing environments.',
      );
      return;
    }
    setState(() {
      _showEnvironmentManager = true;
      _showPackageManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _clearExecutionPageUnlessTests();
    });
    await _loadEnvironments();
  }

  Future<void> _handleOpenPackageManager() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before managing packages.',
      );
      return;
    }
    setState(() {
      _showPackageManager = true;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.packages;
      _clearExecutionPageUnlessTests();
    });
    await _loadPackages();
  }

  Future<void> _handleSelectPackage(PackageInfo package) async {
    setState(() {
      _selectedPackage = package;
      _showPackageManager = true;
      _showEnvironmentManager = false;
      _selectedProject = null;
      _selectedEnvironment = null;
    });
    try {
      final fresh = await _gateway.getPackage(package.name);
      if (!mounted) return;
      setState(() => _selectedPackage = fresh);
    } catch (error) {
      _appendLog('[warn] Could not refresh package details: $error');
    }
  }

  Future<void> _handleSearchPyPI() async {
    final selected = await showSearchPackagesDialog(
      context,
      onSearch: _gateway.searchPackages,
      onLoadVersions: _gateway.listPackageVersions,
    );
    if (selected == null) return;
    AppLogger.info(
      'Install package selected',
      tag: 'Shell',
      data: '${selected.name}==${selected.version}',
    );
    await _runPackageOperation(
      title: 'Installing Package',
      packageName: '${selected.name} ${selected.version}',
      operation: () => _gateway.installPackage(
        selected.name,
        version: selected.version,
      ),
      successMessage: 'Installed package',
    );
  }

  Future<void> _handleInstallRobot() async {
    await _runPackageOperation(
      title: 'Installing Robot Framework',
      packageName: 'robotframework',
      operation: () => _gateway.installPackage('robotframework'),
      successMessage: 'Installed Robot Framework',
    );
  }

  Future<void> _handleUpdatePackage(PackageInfo package) async {
    await _runPackageOperation(
      title: 'Updating Package',
      packageName: package.name,
      operation: () => _gateway.updatePackage(package.name),
      successMessage: 'Updated package',
    );
  }

  Future<void> _handleUninstallPackage(PackageInfo package) async {
    final confirmed = await showUninstallPackageDialog(
      context,
      package: package,
    );
    if (confirmed != true) return;
    await _runPackageOperation(
      title: 'Uninstalling Package',
      packageName: package.name,
      operation: () => _gateway.uninstallPackage(package.name),
      successMessage: 'Uninstalled package',
      clearSelection: true,
    );
  }

  Future<void> _runPackageOperation({
    required String title,
    required String packageName,
    required Future<PackageOperationResult> Function() operation,
    required String successMessage,
    bool clearSelection = false,
  }) async {
    await showPackageProgressDialog(
      context,
      title: title,
      packageName: packageName,
      operation: operation,
      onSuccess: (result) {
        _appendLog('[info] $successMessage "$packageName"');
        setState(() {
          _robotFrameworkInstalled = result.robotFrameworkInstalled;
          _robotFrameworkVersion = result.robotFrameworkVersion;
          if (clearSelection) {
            _selectedPackage = null;
          } else if (result.package != null) {
            _selectedPackage = result.package;
          }
        });
        _loadPackages();
      },
      onError: (error) {
        _appendLog('[error] $error');
      },
    );
  }

  Future<void> _handleSelectEnvironment(EnvironmentInfo environment) async {
    setState(() {
      _selectedEnvironment = environment;
      _selectedProject = null;
      _selectedPackage = null;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _clearExecutionPageUnlessTests();
    });
    try {
      final fresh = await _gateway.getEnvironment(environment.id);
      if (!mounted) return;
      setState(() => _selectedEnvironment = fresh);
    } catch (error) {
      _appendLog('[warn] Could not refresh environment details: $error');
    }
  }

  Future<void> _handleCreateEnvironment() async {
    AppLogger.info('Create environment dialog', tag: 'Shell');
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before creating an environment.',
      );
      return;
    }
    final result = await showCreateEnvironmentDialog(
      context,
      loadInterpreters: _gateway.listPythonInterpreters,
    );
    if (result == null) {
      AppLogger.debug('Create environment cancelled', tag: 'Shell');
      return;
    }
    AppLogger.info(
      'Creating environment',
      tag: 'Shell',
      data: {
        'name': result.name,
        'python': result.pythonInterpreter,
        'installRobot': result.installRobot,
      },
    );
    await _runEnvironmentAction(
      () => _gateway.createEnvironment(
        name: result.name,
        pythonInterpreter: result.pythonInterpreter,
        installRobotFramework: result.installRobot,
      ),
      successMessage: 'Created environment',
      selectResult: true,
    );
  }

  Future<void> _handleImportEnvironment() async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before importing an environment.',
      );
      return;
    }
    final path = await showImportEnvironmentDialog(context);
    if (path == null) return;
    await _runEnvironmentAction(
      () => _gateway.importEnvironment(path),
      successMessage: 'Imported environment',
      selectResult: true,
    );
  }

  Future<void> _handleActivateEnvironment(EnvironmentInfo environment) async {
    await _runEnvironmentAction(
      () => _gateway.activateEnvironment(environment.id),
      successMessage: 'Activated environment',
      selectResult: true,
    );
  }

  Future<void> _handleActivateByName(String name) async {
    final match = _environments.where((item) => item.name == name).toList();
    if (match.isEmpty) return;
    await _handleActivateEnvironment(match.first);
  }

  Future<void> _handleCloneEnvironment(EnvironmentInfo environment) async {
    final name = await showCloneEnvironmentDialog(
      context,
      sourceName: environment.name,
    );
    if (name == null) return;
    await _runEnvironmentAction(
      () => _gateway.cloneEnvironment(
        environmentId: environment.id,
        name: name,
      ),
      successMessage: 'Cloned environment',
      selectResult: true,
    );
  }

  Future<void> _handleDeleteEnvironment(EnvironmentInfo environment) async {
    final deleteFiles = await showDeleteEnvironmentDialog(
      context,
      environment: environment,
    );
    if (deleteFiles == null) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _gateway.deleteEnvironment(
        environmentId: environment.id,
        deleteFiles: deleteFiles,
      );
      if (!mounted) return;
      setState(() {
        if (_selectedEnvironment?.id == environment.id) {
          _selectedEnvironment = null;
        }
        _busy = false;
      });
      _appendLog('[info] Deleted environment "${environment.name}"');
      await _loadEnvironments();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Environment error', error);
    }
  }

  Future<void> _handleSortChanged(EnvironmentSort sort) async {
    setState(() => _environmentSort = sort);
    await _loadEnvironments();
  }

  Future<void> _runEnvironmentAction(
    Future<EnvironmentInfo> Function() action, {
    required String successMessage,
    bool selectResult = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final environment = await action();
      if (!mounted) return;
      setState(() {
        if (selectResult) {
          _selectedEnvironment = environment;
          _selectedProject = null;
          _clearExecutionPageUnlessTests();
        }
        _busy = false;
      });
      _appendLog('[info] $successMessage "${environment.name}"');
      await _loadEnvironments();
      await _loadPackages();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Environment error', error);
    }
  }

  Future<void> _loadFileTree() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() => _fileTree = []);
      return;
    }

    try {
      final tree = await _gateway.listFileTree();
      if (!mounted) return;
      setState(() => _fileTree = tree);
    } catch (error) {
      _appendLog('[warn] Could not load file tree: $error');
    }
  }

  void _trackRecentFile(String path) {
    _recentFiles = [
      path,
      ..._recentFiles.where((item) => item != path),
    ].take(10).toList();
  }

  Future<void> _openFile(String path, {int? line}) async {
    AppLogger.info(
      'Open file',
      tag: 'Shell',
      data: 'path=$path line=$line',
    );
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before editing files.',
      );
      return;
    }

    final existingIndex =
        _editorTabs.indexWhere((tab) => tab.path == path);
    if (existingIndex >= 0) {
      AppLogger.debug('Reusing open tab', tag: 'Shell', data: path);
      setState(() {
        _activeEditorPath = path;
        _showEditorPage = true;
        _jumpToLine = line;
        _editorHover = null;
        _editorReferences = [];
        _editorStatusMessage = null;
      });
      _trackRecentFile(path);
      await _selectTab(path);
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _gateway.readFile(path);
      if (!mounted) return;
      setState(() {
        _editorTabs = [
          ..._editorTabs,
          EditorTabInfo(
            path: file.path,
            content: file.content,
            savedContent: file.content,
            mtime: file.mtime,
          ),
        ];
        _activeEditorPath = file.path;
        _showEditorPage = true;
        _jumpToLine = line;
        _editorHover = null;
        _editorReferences = [];
        _editorStatusMessage = null;
        _busy = false;
      });
      _trackRecentFile(file.path);
      await _loadOutline(file.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] Could not open file: $error');
      await _showError('Open file', error);
    }
  }

  Future<bool> _confirmDiscard(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: Text(
          'Save changes to "${_fileNameFromPath(path)}" before closing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _fileNameFromPath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Future<void> _closeTab(String path) async {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;

    final tab = _editorTabs[tabIndex];
    if (tab.isDirty) {
      final discard = await _confirmDiscard(path);
      if (!discard) return;
    }

    final updated = [..._editorTabs]..removeAt(tabIndex);
    String? nextPath;
    setState(() {
      _editorTabs = updated;
      if (_activeEditorPath == path) {
        if (updated.isEmpty) {
          _activeEditorPath = null;
          _documentOutline = [];
          _selectedOutlineSymbol = null;
          _showEditorPage = false;
        } else {
          nextPath = updated.last.path;
          _activeEditorPath = nextPath;
        }
      }
      _editorHover = null;
      _editorReferences = [];
    });
    if (nextPath != null) {
      await _loadOutline(nextPath!);
    }
  }

  Future<void> _selectTab(String path) async {
    if (_activeEditorPath == path) {
      await _checkExternalChanges(path);
      return;
    }

    setState(() {
      _activeEditorPath = path;
      _showEditorPage = true;
      _jumpToLine = null;
      _editorHover = null;
      _editorReferences = [];
      _editorStatusMessage = null;
    });
    await _checkExternalChanges(path);
    await _loadOutline(path);
  }

  Future<void> _checkExternalChanges(String path) async {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    final tab = _editorTabs[tabIndex];

    try {
      final fresh = await _gateway.readFile(path);
      if (!mounted) return;
      if (fresh.mtime == tab.mtime) return;

      if (!tab.isDirty) {
        setState(() {
          tab.content = fresh.content;
          tab.savedContent = fresh.content;
          tab.mtime = fresh.mtime;
        });
        return;
      }

      final reload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('File Changed Externally'),
          content: Text(
            '"${_fileNameFromPath(path)}" was modified outside the editor. Reload and lose unsaved changes?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (reload == true && mounted) {
        setState(() {
          tab.content = fresh.content;
          tab.savedContent = fresh.content;
          tab.mtime = fresh.mtime;
        });
      }
    } catch (error) {
      _appendLog('[warn] Could not check external changes: $error');
    }
  }

  void _onContentChanged(String path, String content) {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    setState(() {
      _editorTabs[tabIndex].content = content;
    });
  }

  Future<void> _saveActive() async {
    final path = _activeEditorPath;
    if (path == null) return;
    await _saveTab(path);
  }

  Future<void> _saveAll() async {
    for (final tab in _editorTabs) {
      if (tab.isDirty) {
        await _saveTab(tab.path);
      }
    }
  }

  Future<void> _saveTab(String path) async {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    final tab = _editorTabs[tabIndex];
    if (!tab.isDirty) {
      AppLogger.debug('Save skipped (clean)', tag: 'Shell', data: path);
      return;
    }

    AppLogger.info(
      'Saving file',
      tag: 'Shell',
      data: 'path=$path bytes=${tab.content.length}',
    );
    try {
      final result = await _gateway.writeFile(
        path: path,
        content: tab.content,
      );
      if (!mounted) return;
      setState(() {
        tab.savedContent = tab.content;
        tab.mtime = result.mtime;
        _editorStatusMessage = 'Saved ${_fileNameFromPath(path)}';
      });
      _appendLog('[info] Saved "$path"');
    } catch (error) {
      _appendLog('[error] Save failed: $error');
      await _showError('Save file', error);
    }
  }

  Future<void> _loadOutline(String path) async {
    setState(() {
      _loadingOutline = true;
      _selectedOutlineSymbol = null;
    });
    try {
      final symbols = await _gateway.documentSymbols(path);
      if (!mounted) return;
      setState(() {
        _documentOutline = symbols;
        _loadingOutline = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentOutline = [];
        _loadingOutline = false;
      });
      _appendLog('[warn] Could not load outline: $error');
    }
  }

  String? _extractWordAtCursor(String content, int line, int column) {
    final lines = content.split('\n');
    if (line < 1 || line > lines.length) return null;
    final text = lines[line - 1];
    if (text.isEmpty) return null;

    final offset = (column - 1).clamp(0, text.length);
    final pattern = RegExp(r'\w+|\$\{[^}]+\}');
    String? matchAt(int index) {
      for (final match in pattern.allMatches(text)) {
        if (index >= match.start && index <= match.end) {
          return match.group(0);
        }
      }
      return null;
    }

    final direct = matchAt(offset);
    if (direct != null) return direct;

    for (var delta = 1; delta <= text.length; delta++) {
      if (offset - delta >= 0) {
        final left = matchAt(offset - delta);
        if (left != null) return left;
      }
      if (offset + delta <= text.length) {
        final right = matchAt(offset + delta);
        if (right != null) return right;
      }
    }
    return null;
  }

  String? _editorTokenName() {
    final outline = _selectedOutlineSymbol?.name;
    if (outline != null && outline.isNotEmpty) return outline;

    final search = _selectedSymbol?.name;
    if (search != null && search.isNotEmpty) return search;

    final tab = _activeEditorTab;
    if (tab == null) return null;
    return _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
  }

  Future<void> _editorGoToDefinition() async {
    final token = _editorTokenName();
    if (token == null) {
      setState(() {
        _editorStatusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editorStatusMessage = null;
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final definition = await _gateway.languageDefinition(name: token);
      if (!mounted) return;
      if (definition != null) {
        await _openFile(definition.filePath, line: definition.line);
      } else {
        setState(() {
          _editorStatusMessage = 'No definition found for "$token".';
        });
      }
    } catch (error) {
      _appendLog('[warn] Definition lookup failed: $error');
      await _showError('Go to Definition', error);
    }
  }

  Future<void> _editorFindReferences() async {
    final token = _editorTokenName();
    if (token == null) {
      setState(() {
        _editorStatusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editorStatusMessage = null;
      _editorReferences = [];
      _editorHover = null;
    });

    try {
      final refs = await _gateway.languageReferences(name: token);
      if (!mounted) return;
      setState(() {
        _editorReferences = refs;
        if (refs.isEmpty) {
          _editorStatusMessage = 'No references found for "$token".';
        }
      });
    } catch (error) {
      _appendLog('[warn] References lookup failed: $error');
      await _showError('Find References', error);
    }
  }

  Future<void> _editorHoverLookup() async {
    final token = _editorTokenName();
    if (token == null) {
      setState(() {
        _editorStatusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editorStatusMessage = null;
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final hover = await _gateway.languageHover(name: token);
      if (!mounted) return;
      setState(() {
        _editorHover = hover;
        if (hover == null) {
          _editorStatusMessage = 'No hover info for "$token".';
        }
      });
    } catch (error) {
      _appendLog('[warn] Hover lookup failed: $error');
      await _showError('Hover Info', error);
    }
  }

  Future<void> _revealCurrentFile() async {
    final path = _activeEditorPath;
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    setState(() {
      _editorStatusMessage = 'Path: $path (copied to clipboard)';
    });
  }

  void _handleContinueWorking() {
    if (_editorTabs.isNotEmpty) {
      final path = _activeEditorPath ?? _editorTabs.first.path;
      setState(() => _showEditorPage = true);
      _selectTab(path);
      return;
    }
    if (_recentFiles.isNotEmpty) {
      _openFile(_recentFiles.first);
    }
  }

  Future<void> _openSearchPanel({SymbolKind? kind}) async {
    if (_activeWorkspace == null) {
      await _showError(
        'Workspace required',
        'Open a workspace before searching symbols.',
      );
      return;
    }
    setState(() {
      _activePanel =
          kind == SymbolKind.keyword ? SidebarPanel.keywords : SidebarPanel.search;
      _showSearchPage = true;
      _showEditorPage = false;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showExecutionPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _selectedReport = null;
      if (kind != null) {
        _searchKind = kind;
      }
    });
    _loadIndexStatus();
  }

  Future<void> _loadIndexStatus() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _indexStatus = null;
        _loadingIndexStatus = false;
      });
      return;
    }

    setState(() => _loadingIndexStatus = true);
    try {
      final status = await _gateway.getIndexStatus();
      if (!mounted) return;
      setState(() {
        _indexStatus = status;
        _loadingIndexStatus = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingIndexStatus = false);
      _appendLog('[warn] Could not load index status: $error');
    }
  }

  Future<void> _rebuildIndex() async {
    if (_activeWorkspace == null) return;
    setState(() => _loadingIndexStatus = true);
    try {
      final status = await _gateway.rebuildIndex();
      if (!mounted) return;
      setState(() {
        _indexStatus = status;
        _loadingIndexStatus = false;
      });
      _appendLog('[info] Symbol index rebuilt');
      if (_searchQuery.trim().isNotEmpty) {
        await _runSearch();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingIndexStatus = false);
      _appendLog('[error] Index rebuild failed: $error');
      await _showError('Index rebuild', error);
    }
  }

  Future<void> _runSearch() async {
    if (_activeWorkspace == null || _backendStatus != 'connected') return;

    setState(() {
      _isSearching = true;
      _selectedSymbol = null;
      _hoverInfo = null;
      _references = [];
      _navigationMessage = null;
    });
    try {
      final results = await _gateway.searchSymbols(
        query: _searchQuery.trim(),
        kind: _searchKind,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      _appendLog('[warn] Search failed: $error');
      await _showError('Search', error);
    }
  }

  void _selectSymbol(IndexedSymbolInfo symbol) {
    setState(() {
      _selectedSymbol = symbol;
      _hoverInfo = null;
      _references = [];
      _navigationMessage = null;
    });
  }

  Future<void> _goToDefinition() async {
    final symbol = _selectedSymbol;
    if (symbol == null) return;

    setState(() {
      _isLoadingLanguage = true;
      _navigationMessage = null;
    });
    try {
      final definition = await _gateway.languageDefinition(
        name: symbol.name,
        symbolId: symbol.id,
        kind: symbol.kind,
      );
      if (!mounted) return;
      setState(() => _isLoadingLanguage = false);
      if (definition != null) {
        await _openFile(definition.filePath, line: definition.line);
      } else {
        setState(() {
          _navigationMessage = 'No definition found for "${symbol.name}".';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingLanguage = false);
      _appendLog('[warn] Definition lookup failed: $error');
      await _showError('Go to Definition', error);
    }
  }

  Future<void> _findReferences() async {
    final symbol = _selectedSymbol;
    if (symbol == null) return;

    setState(() {
      _isLoadingLanguage = true;
      _references = [];
    });
    try {
      final refs = await _gateway.languageReferences(
        name: symbol.name,
        symbolId: symbol.id,
        kind: symbol.kind,
      );
      if (!mounted) return;
      setState(() {
        _references = refs;
        _isLoadingLanguage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingLanguage = false);
      _appendLog('[warn] References lookup failed: $error');
      await _showError('Find References', error);
    }
  }

  Future<void> _showHover() async {
    final symbol = _selectedSymbol;
    if (symbol == null) return;

    setState(() {
      _isLoadingLanguage = true;
      _hoverInfo = null;
    });
    try {
      final hover = await _gateway.languageHover(
        name: symbol.name,
        symbolId: symbol.id,
        kind: symbol.kind,
      );
      if (!mounted) return;
      setState(() {
        _hoverInfo = hover;
        _isLoadingLanguage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingLanguage = false);
      _appendLog('[warn] Hover lookup failed: $error');
      await _showError('Hover Info', error);
    }
  }

  _CenterView get _centerView {
    if (_activeWorkspace == null) return _CenterView.welcome;
    if (_showExecutionPage || _activePanel == SidebarPanel.tests) {
      return _CenterView.execution;
    }
    if (_showSearchPage ||
        _activePanel == SidebarPanel.search ||
        _activePanel == SidebarPanel.keywords) {
      return _CenterView.search;
    }
    if (_showEditorPage &&
        _editorTabs.isNotEmpty &&
        _activeEditorPath != null) {
      return _CenterView.editor;
    }
    if (_showEnvironmentManager) return _CenterView.manager;
    if (_selectedPackage != null) return _CenterView.packageDetail;
    if (_showPackageManager || _activePanel == SidebarPanel.packages) {
      return _CenterView.packages;
    }
    if (_showReportsPage || _activePanel == SidebarPanel.reports) {
      return _CenterView.reports;
    }
    if (_selectedEnvironment != null) return _CenterView.environment;
    if (_selectedProject != null) return _CenterView.project;
    return _CenterView.placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _backendStatus == 'connected';
    final activeEnvironment = _activeEnvironment;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              AppToolbar(
                panelTitle: _activePanel.label,
                workspaceLabel: _activeWorkspace?.name ?? 'No workspace',
                environmentLabel: !connected
                    ? 'Backend offline'
                    : activeEnvironment?.name ?? 'No environment',
                environmentNames:
                    _environments.map((item) => item.name).toList(),
                selectedEnvironmentName: activeEnvironment?.name,
                onEnvironmentSelected: _handleActivateByName,
                onManageEnvironments: _handleManageEnvironments,
                robotFrameworkInstalled: _robotFrameworkInstalled,
                robotFrameworkVersion: _robotFrameworkVersion,
                onInstallRobotFramework: _handleInstallRobot,
                onOpenPackageManager: _handleOpenPackageManager,
                backendConnected: connected,
                backendVersion: _backendVersion,
                onRun: _handleRunFile,
                onRunProject: _handleRunProject,
                onStop: _handleStopExecution,
                isExecutionRunning: _executionStatus.isActive,
                executionStatusLabel: _executionStatus.label,
                executionElapsedLabel: _elapsedLabel,
                onOpenWorkspace: _handleOpenWorkspace,
                onNewWorkspace: _handleNewWorkspace,
                onOpenSearch: () => _openSearchPanel(),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSidebar(
                      activePanel: _activePanel,
                      onPanelSelected: (panel) {
                        setState(() {
                          _activePanel = panel;
                          if (panel == SidebarPanel.tests) {
                            _showExecutionPage = true;
                            _showEditorPage = false;
                          } else {
                            _showExecutionPage = false;
                          }
                          if (panel == SidebarPanel.search ||
                              panel == SidebarPanel.keywords) {
                            _showSearchPage = true;
                            _showEditorPage = false;
                            _showEnvironmentManager = false;
                            _showPackageManager = false;
                            _showReportsPage = false;
                            _selectedProject = null;
                            _selectedEnvironment = null;
                            _selectedPackage = null;
                            _selectedReport = null;
                            if (panel == SidebarPanel.keywords) {
                              _searchKind = SymbolKind.keyword;
                            }
                          } else {
                            _showSearchPage = false;
                            if (panel == SidebarPanel.explorer &&
                                _editorTabs.isNotEmpty &&
                                _activeEditorPath != null) {
                              _showEditorPage = true;
                            } else if (panel == SidebarPanel.packages ||
                                panel == SidebarPanel.reports) {
                              _showEditorPage = false;
                            }
                          }
                        });
                        if (panel == SidebarPanel.packages) {
                          _handleOpenPackageManager();
                        } else if (panel == SidebarPanel.reports) {
                          _openReports();
                        } else if (panel == SidebarPanel.tests) {
                          _loadExecutionHistory();
                        } else if (panel == SidebarPanel.search ||
                            panel == SidebarPanel.keywords) {
                          _loadIndexStatus();
                        }
                      },
                    ),
                    SidePanel(
                      panel: _activePanel,
                      workspace: _activeWorkspace,
                      projects: _projects,
                      isLoadingProjects: _loadingProjects,
                      selectedProject: _selectedProject,
                      onSelectProject: _handleSelectProject,
                      onNewProject: _handleNewProject,
                      onImportProject: _handleImportProject,
                      environments: _environments,
                      isLoadingEnvironments: _loadingEnvironments,
                      selectedEnvironment: _selectedEnvironment,
                      onSelectEnvironment: _handleSelectEnvironment,
                      onManageEnvironments: _handleManageEnvironments,
                      onOpenPackageManager: _handleOpenPackageManager,
                      recentRuns: _reportRuns.take(5).toList(),
                      onSelectReport: _selectReport,
                      onOpenReports: _openReports,
                      backendVersion: _backendVersion,
                      fileTree: _fileTree,
                      onOpenFile: _openFile,
                    ),
                    Expanded(child: _buildCenter()),
                  ],
                ),
              ),
              BottomPanel(
                logLines: _logLines,
                executionLines: _executionLines,
                forceExecutionTab: _executionStatus.isActive,
              ),
              StatusBar(
                backendConnected: connected,
                backendVersion: _backendVersion,
                workspaceName: _activeWorkspace?.name,
                fileName: _centerView == _CenterView.editor
                    ? _activeEditorTab?.fileName
                    : null,
                cursorLabel: _centerView == _CenterView.editor
                    ? 'Ln $_cursorLine, Col $_cursorColumn'
                    : null,
                dirty: _centerView == _CenterView.editor
                    ? (_activeEditorTab?.isDirty ?? false)
                    : false,
              ),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    return switch (_centerView) {
      _CenterView.welcome => WelcomeScreen(
          recentWorkspaces: _recentWorkspaces,
          recentProjects: _recentProjects,
          isLoadingRecent: _loadingRecent,
          onNewWorkspace: _handleNewWorkspace,
          onOpenWorkspace: _handleOpenWorkspace,
          onOpenRecentWorkspace: _handleOpenRecentWorkspace,
          onOpenRecentProject: _handleOpenRecentProject,
          onNewProject: _handleNewProject,
          onImportProject: _handleImportProject,
          onManageEnvironments: _handleManageEnvironments,
          activeEnvironmentLabel: _activeEnvironment?.name,
          recentRuns: _executionHistory.take(3).toList(),
          runningStatus:
              _executionStatus.isActive ? _executionStatus : null,
          lastRunLabel: _executionHistory.isNotEmpty
              ? _executionHistory.first.suite
              : null,
          dashboard: _reportsDashboard,
          workspaceOpen: _activeWorkspace != null,
          indexStatus: _indexStatus,
          isLoadingIndexStatus: _loadingIndexStatus,
          onRebuildIndex: _activeWorkspace != null ? _rebuildIndex : null,
          recentFiles: _recentFiles,
          openEditors: _editorTabs.map((tab) => tab.path).toList(),
          onOpenRecentFile: _activeWorkspace == null ? null : _openFile,
          onContinueWorking:
              _activeWorkspace == null ? null : _handleContinueWorking,
        ),
      _CenterView.manager => EnvironmentManagerPage(
          environments: _environments,
          isLoading: _loadingEnvironments,
          sort: _environmentSort,
          selected: _selectedEnvironment,
          onSortChanged: _handleSortChanged,
          onSelect: _handleSelectEnvironment,
          onCreate: _handleCreateEnvironment,
          onImport: _handleImportEnvironment,
          onActivate: _handleActivateEnvironment,
          onClone: _handleCloneEnvironment,
          onDelete: _handleDeleteEnvironment,
        ),
      _CenterView.packages => PackageManagerPage(
          packages: _packages,
          isLoading: _loadingPackages,
          sort: _packageSort,
          query: _packageQuery,
          selected: _selectedPackage,
          robotInstalled: _robotFrameworkInstalled,
          robotVersion: _robotFrameworkVersion,
          hasActiveEnvironment: _activeEnvironment != null,
          onQueryChanged: (value) {
            setState(() => _packageQuery = value);
            _loadPackages();
          },
          onSortChanged: (sort) {
            setState(() => _packageSort = sort);
            _loadPackages();
          },
          onRefresh: _loadPackages,
          onSearchPyPI: _handleSearchPyPI,
          onSelect: _handleSelectPackage,
          onUpdate: _handleUpdatePackage,
          onUninstall: _handleUninstallPackage,
          onInstallRobot: _handleInstallRobot,
        ),
      _CenterView.packageDetail => PackageDetailsPanel(
          package: _selectedPackage!,
          onUpdate: _selectedPackage!.updateAvailable
              ? () => _handleUpdatePackage(_selectedPackage!)
              : null,
          onUninstall: () => _handleUninstallPackage(_selectedPackage!),
          onBack: () {
            setState(() {
              _selectedPackage = null;
              _showPackageManager = true;
            });
          },
        ),
      _CenterView.environment => EnvironmentDetailsPanel(
          environment: _selectedEnvironment!,
          onActivate: _selectedEnvironment!.active
              ? null
              : () => _handleActivateEnvironment(_selectedEnvironment!),
          onClone: () => _handleCloneEnvironment(_selectedEnvironment!),
          onDelete: () => _handleDeleteEnvironment(_selectedEnvironment!),
          onManage: _handleManageEnvironments,
        ),
      _CenterView.project => ProjectDetailsPanel(project: _selectedProject!),
      _CenterView.execution => ExecutionPage(
          consoleLines: _executionLines,
          history: _executionHistory,
          isLoadingHistory: _loadingHistory,
          status: _executionStatus,
          currentRun: _currentExecution,
          elapsedLabel: _elapsedLabel,
          onRefreshHistory: _loadExecutionHistory,
          onRunFile: _handleRunFile,
          onRunProject: _handleRunProject,
          onStop: _handleStopExecution,
        ),
      _CenterView.reports => ReportsPage(
          runs: _reportRuns,
          isLoading: _loadingReports,
          dashboard: _reportsDashboard,
          isLoadingDashboard: _loadingDashboard,
          selected: _selectedReport,
          onRefresh: _loadReports,
          onSelect: _selectReport,
          onOpenLog: _openReportLog,
          onOpenReport: _openReportHtml,
          onReveal: _revealReport,
          onDelete: _deleteSelectedReport,
        ),
      _CenterView.search => SearchPage(
          query: _searchQuery,
          kind: _searchKind,
          results: _searchResults,
          isSearching: _isSearching,
          indexStatus: _indexStatus,
          isLoadingStatus: _loadingIndexStatus,
          selected: _selectedSymbol,
          hover: _hoverInfo,
          references: _references,
          isLoadingLanguage: _isLoadingLanguage,
          navigationMessage: _navigationMessage,
          onQueryChanged: (value) => setState(() => _searchQuery = value),
          onKindChanged: (value) => setState(() => _searchKind = value),
          onSearch: _runSearch,
          onSelect: _selectSymbol,
          onGoToDefinition: _goToDefinition,
          onFindReferences: _findReferences,
          onShowHover: _showHover,
          onRebuildIndex: _rebuildIndex,
          onOpenPlaceholder: _selectedSymbol == null
              ? null
              : () => _openFile(
                    _selectedSymbol!.filePath,
                    line: _selectedSymbol!.line,
                  ),
        ),
      _CenterView.editor => EditorPage(
          tabs: _editorTabs,
          activePath: _activeEditorPath,
          outline: _documentOutline,
          isLoadingOutline: _loadingOutline,
          wordWrap: _wordWrap,
          hover: _editorHover,
          references: _editorReferences,
          statusMessage: _editorStatusMessage,
          jumpToLine: _jumpToLine,
          onSelectTab: _selectTab,
          onCloseTab: _closeTab,
          onContentChanged: _onContentChanged,
          onSave: _saveActive,
          onSaveAll: _saveAll,
          onToggleWordWrap: () => setState(() => _wordWrap = !_wordWrap),
          onGoToDefinition: _editorGoToDefinition,
          onFindReferences: _editorFindReferences,
          onHover: _editorHoverLookup,
          onOutlineSelect: (symbol) {
            setState(() {
              _selectedOutlineSymbol = symbol;
              _jumpToLine = symbol.line;
            });
          },
          onFind: () {},
          onReplace: () {},
          onReveal: _revealCurrentFile,
          onCursorChanged: (line, column) {
            setState(() {
              _cursorLine = line;
              _cursorColumn = column;
              if (_activeEditorTab != null) {
                _activeEditorTab!.cursorLine = line;
                _activeEditorTab!.cursorColumn = column;
              }
            });
          },
        ),
      _CenterView.placeholder => _WorkspaceOpenPlaceholder(
          workspace: _activeWorkspace!,
          onNewProject: _handleNewProject,
          onImportProject: _handleImportProject,
          onManageEnvironments: _handleManageEnvironments,
        ),
    };
  }
}

class _WorkspaceOpenPlaceholder extends StatelessWidget {
  const _WorkspaceOpenPlaceholder({
    required this.workspace,
    required this.onNewProject,
    required this.onImportProject,
    required this.onManageEnvironments,
  });

  final WorkspaceInfo workspace;
  final VoidCallback onNewProject;
  final VoidCallback onImportProject;
  final VoidCallback onManageEnvironments;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            workspace.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Select a project or environment, or create one to get started.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onNewProject,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Project'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onImportProject,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Import Project'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onManageEnvironments,
                icon: const Icon(Icons.memory_outlined, size: 16),
                label: const Text('Environments'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
