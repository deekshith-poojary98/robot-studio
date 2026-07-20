import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../git/source_control_page.dart';
import '../packages/package_details_panel.dart';
import '../packages/package_manager_page.dart';
import '../packages/package_progress_dialog.dart';
import '../packages/search_packages_dialog.dart';
import '../packages/uninstall_package_dialog.dart';
import '../panels/bottom_panel.dart';
import '../panels/side_panel.dart';
import '../plugins/plugin_details_panel.dart';
import '../plugins/plugin_manager_page.dart';
import '../project/import_project_dialog.dart';
import '../project/new_project_dialog.dart';
import '../project/project_details_panel.dart';
import '../reports/delete_run_dialog.dart';
import '../reports/reports_page.dart';
import '../search/search_page.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/sidebar_panel.dart';
import '../toolbar/app_toolbar.dart';
import '../widgets/guidance_dialog.dart';
import '../workspace/new_workspace_dialog.dart';
import '../workspace/welcome_screen.dart';
import 'controllers/editor_shell_controller.dart';
import 'controllers/execution_shell_controller.dart';
import 'controllers/workspace_shell_controller.dart';
import 'status_bar.dart';

enum _CenterView {
  welcome,
  placeholder,
  project,
  environment,
  manager,
  packages,
  plugins,
  sourceControl,
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

  late final TransportGateway _gateway;
  late final WorkspaceShellController _workspace;
  late final ExecutionShellController _execution;
  late final EditorShellController _editor;

  void _notify() {
    if (mounted) setState(() {});
  }

  void _appendLog(String line) => _workspace.append(line);
  bool _showEnvironmentManager = false;
  EnvironmentSort _environmentSort = EnvironmentSort.active;
  bool _showPackageManager = false;
  bool _showPluginManager = false;
  PluginInfo? _selectedPlugin;
  List<PluginInfo> _plugins = [];
  bool _loadingPlugins = false;
  bool _showSourceControl = false;
  GitStatusInfo? _gitStatus;
  List<GitBranchInfo> _gitBranches = [];
  List<GitCommitInfo> _gitHistory = [];
  GitCommitInfo? _selectedGitCommit;
  GitCommitDetailInfo? _selectedGitCommitDetail;
  GitDiffInfo? _gitDiff;
  String? _selectedGitDiffFile;
  final Set<String> _selectedGitFiles = {};
  bool _loadingGit = false;
  bool _gitBusy = false;
  bool _loadingGitHistory = false;
  bool _loadingGitDiff = false;
  late final TextEditingController _gitCommitController;
  PackageInfo? _selectedPackage;
  List<PackageInfo> _packages = [];
  PackageSort _packageSort = PackageSort.name;
  String _packageQuery = '';
  bool _robotFrameworkInstalled = false;
  String? _robotFrameworkVersion;
  bool _loadingPackages = false;
  bool _busy = false;

  ProjectInfo? _selectedProject;
  EnvironmentInfo? _selectedEnvironment;
  bool _showExecutionPage = false;
  int _revealExecutionLogsToken = 0;
  bool _showReportsPage = false;
  String _searchQuery = '';
  SymbolKind? _searchKind;
  List<IndexedSymbolInfo> _searchResults = [];
  List<IndexedSymbolInfo> _testSuites = [];
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
  bool _showEditorPage = false;
  HoverInfo? _editorHover;
  List<SymbolReferenceInfo> _editorReferences = [];

  String get _backendStatus => _workspace.backendStatus;
  List<String> get _logLines => _workspace.logLines;
  WorkspaceInfo? get _activeWorkspace => _workspace.activeWorkspace;
  List<ProjectInfo> get _projects => _workspace.projects;
  List<EnvironmentInfo> get _environments => _workspace.environments;
  List<WorkspaceInfo> get _recentWorkspaces => _workspace.recentWorkspaces;
  List<ProjectInfo> get _recentProjects => _workspace.recentProjects;
  bool get _loadingRecent => _workspace.loadingRecent;
  bool get _loadingProjects => _workspace.loadingProjects;
  bool get _loadingEnvironments => _workspace.loadingEnvironments;

  List<String> get _executionLines => _execution.executionLines;
  List<ExecutionInfo> get _executionHistory => _execution.executionHistory;
  ExecutionStatus get _executionStatus => _execution.executionStatus;
  ExecutionInfo? get _currentExecution => _execution.currentExecution;
  bool get _loadingHistory => _execution.loadingHistory;
  List<ExecutionInfo> get _reportRuns => _execution.reportRuns;
  ExecutionInfo? get _selectedReport => _execution.selectedReport;
  DashboardSummary? get _reportsDashboard => _execution.reportsDashboard;
  bool get _loadingReports => _execution.loadingReports;
  bool get _loadingDashboard => _execution.loadingDashboard;

  List<EditorTabInfo> get _editorTabs => _editor.tabs;
  String? get _activeEditorPath => _editor.activePath;
  List<IndexedSymbolInfo> get _documentOutline => _editor.documentOutline;
  bool get _loadingOutline => _editor.loadingOutline;
  bool get _wordWrap => _editor.wordWrap;
  String? get _editorStatusMessage => _editor.statusMessage;
  int? get _jumpToLine => _editor.jumpToLine;
  int get _cursorLine => _editor.cursorLine;
  int get _cursorColumn => _editor.cursorColumn;
  List<FileTreeNode> get _fileTree => _editor.fileTree;
  List<String> get _recentFiles => _editor.recentFiles;
  IndexedSymbolInfo? get _selectedOutlineSymbol => _editor.selectedOutlineSymbol;
  List<CompletionItemInfo> get _completionItems => _editor.completionItems;
  List<DiagnosticInfo> get _editorDiagnostics => _editor.diagnostics;
  List<DiagnosticInfo> get _workspaceProblems => _editor.workspaceProblems;
  SignatureHelpInfo? get _signatureHelp => _editor.signatureHelp;
  IndexedSymbolInfo? get _peekDefinition => _editor.peekDefinition;
  bool get _loadingLanguageFeatures => _editor.loadingLanguageFeatures;

  EnvironmentInfo? get _activeEnvironment => _workspace.activeEnvironment;
  EditorTabInfo? get _activeEditorTab => _editor.activeTab;

  String get _elapsedLabel => _execution.elapsedLabel;

  @override
  void initState() {
    super.initState();
    _gitCommitController = TextEditingController();
    _gitCommitController.addListener(() {
      if (mounted) setState(() {});
    });
    _gateway = widget._gateway ?? RestTransportGateway();
    _workspace = WorkspaceShellController(
      gateway: _gateway,
      notify: _notify,
      isMounted: () => mounted,
      appendLog: _appendLog,
    );
    _execution = ExecutionShellController(
      gateway: _gateway,
      notify: _notify,
      isMounted: () => mounted,
      appendLog: _appendLog,
      onRunFinished: _handleRunFinished,
      workspace: () => _workspace.activeWorkspace,
      backendConnected: () => _workspace.backendConnected,
    );
    _editor = EditorShellController(
      gateway: _gateway,
      notify: _notify,
      isMounted: () => mounted,
      workspace: () => _workspace.activeWorkspace,
    );
    AppLogger.info('AppShell init', tag: 'Shell');
    _bootstrap();
  }

  @override
  void dispose() {
    AppLogger.debug('AppShell dispose', tag: 'Shell');
    _gitCommitController.dispose();
    _execution.dispose();
    _editor.dispose();
    super.dispose();
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
        _workspace.backendStatus = 'connected';
        _workspace.backendVersion = health.version;
        _workspace.logLines = [
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
        _workspace.backendStatus = 'offline';
        _workspace.logLines = [
          '[error] Backend unavailable: $error',
          '[info] Start the backend with: python -m robot_studio.main',
        ];
      });
    }
  }

  Future<void> _loadRecent() async {
    if (_backendStatus != 'connected') {
      setState(() {
        _workspace.loadingRecent = false;
        _workspace.recentWorkspaces = [];
        _workspace.recentProjects = [];
      });
      return;
    }

    setState(() => _workspace.loadingRecent = true);
    try {
      final workspaces = await _gateway.listRecentWorkspaces();
      final projects = await _gateway.listRecentProjects();
      if (!mounted) return;
      setState(() {
        _workspace.recentWorkspaces = workspaces;
        _workspace.recentProjects = projects;
        _workspace.loadingRecent = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workspace.loadingRecent = false;
        _appendLog('[warn] Could not load recent items: $error');
      });
    }
  }

  Future<void> _loadProjects() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _workspace.projects = [];
        _workspace.loadingProjects = false;
      });
      return;
    }

    setState(() => _workspace.loadingProjects = true);
    try {
      final projects = await _gateway.listProjects();
      if (!mounted) return;
      setState(() {
        _workspace.projects = projects;
        _workspace.loadingProjects = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workspace.loadingProjects = false;
        _appendLog('[warn] Could not load projects: $error');
      });
    }
  }

  Future<void> _loadEnvironments() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _workspace.environments = [];
        _workspace.loadingEnvironments = false;
        _selectedEnvironment = null;
      });
      return;
    }

    setState(() => _workspace.loadingEnvironments = true);
    try {
      final environments = await _gateway.listEnvironments(
        sort: _environmentSort,
      );
      if (!mounted) return;
      setState(() {
        _workspace.environments = environments;
        _workspace.loadingEnvironments = false;
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
        _workspace.loadingEnvironments = false;
        _appendLog('[warn] Could not load environments: $error');
      });
    }
  }

  Future<void> _loadPackages() async {
    if (_workspace.activeWorkspace == null ||
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

  Future<void> _loadPlugins({bool refresh = false}) async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _plugins = [];
        _loadingPlugins = false;
        _selectedPlugin = null;
      });
      return;
    }

    setState(() => _loadingPlugins = true);
    try {
      final plugins = refresh
          ? await _gateway.refreshPlugins()
          : await _gateway.listPlugins();
      if (!mounted) return;
      setState(() {
        _plugins = plugins;
        _loadingPlugins = false;
        if (_selectedPlugin != null) {
          final match =
              plugins.where((item) => item.id == _selectedPlugin!.id).toList();
          _selectedPlugin = match.isEmpty ? null : match.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingPlugins = false);
      _appendLog('[warn] Could not load plugins: $error');
    }
  }

  Future<void> _handleOpenPluginManager() async {
    if (!await _ensureWorkspace(message: 'Open a workspace before managing plugins.')) return;
    setState(() {
      _showPluginManager = true;
      _showSourceControl = false;
      _showReportsPage = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.plugins;
      _clearExecutionPageUnlessTests();
    });
    await _loadPlugins();
  }

  Map<String, GitFileStatus> get _gitFileStatuses {
    final statuses = <String, GitFileStatus>{};
    for (final change in _gitStatus?.changes ?? const []) {
      statuses[change.path] = change.status;
    }
    return statuses;
  }

  List<String> get _gitBranchNames =>
      _gitBranches.where((branch) => !branch.remote).map((b) => b.name).toList();

  Future<void> _loadGitStatus() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _gitStatus = null;
        _gitBranches = [];
        _loadingGit = false;
      });
      return;
    }

    setState(() => _loadingGit = true);
    try {
      final status = await _gateway.getGitStatus();
      final branches = status.repository.isRepository
          ? await _gateway.getGitBranches()
          : <GitBranchInfo>[];
      if (!mounted) return;
      setState(() {
        _gitStatus = status;
        _gitBranches = branches;
        _loadingGit = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingGit = false);
      _appendLog('[warn] Could not load git status: $error');
    }
  }

  Future<void> _loadGitHistory() async {
    if (_gitStatus?.repository.isRepository != true) return;
    setState(() => _loadingGitHistory = true);
    try {
      final history = await _gateway.getGitHistory(limit: 50);
      if (!mounted) return;
      setState(() {
        _gitHistory = history;
        _loadingGitHistory = false;
        if (_selectedGitCommit != null) {
          final match = history
              .where((item) => item.hash == _selectedGitCommit!.hash)
              .toList();
          _selectedGitCommit = match.isEmpty ? null : match.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingGitHistory = false);
      _appendLog('[warn] Could not load git history: $error');
    }
  }

  Future<void> _loadGitDiff(String filePath) async {
    setState(() {
      _loadingGitDiff = true;
      _selectedGitDiffFile = filePath;
    });
    try {
      final diff = await _gateway.getGitDiff(filePath: filePath);
      if (!mounted) return;
      setState(() {
        _gitDiff = diff;
        _loadingGitDiff = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingGitDiff = false);
      await _showError('Git diff', error);
    }
  }

  Future<void> _handleOpenSourceControl() async {
    if (!await _ensureWorkspace(message: 'Open a workspace before using source control.')) return;
    setState(() {
      _showSourceControl = true;
      _showReportsPage = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.sourceControl;
      _clearExecutionPageUnlessTests();
    });
    await _refreshGit();
  }

  Future<void> _refreshGit() async {
    await _loadGitStatus();
    if (_gitStatus?.repository.isRepository == true) {
      await _loadGitHistory();
    }
  }

  Future<void> _handleGitInit() async {
    setState(() => _gitBusy = true);
    try {
      await _gateway.initGitRepository();
      await _refreshGit();
      _appendLog('[info] Git repository initialized');
    } catch (error) {
      await _showError('Initialize Git repository', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitCommit({List<String>? files}) async {
    final message = _gitCommitController.text.trim();
    if (message.isEmpty) {
      await _showError('Commit', 'Commit message is required.');
      return;
    }
    if (_gitStatus?.repository.isRepository != true) {
      await _showError('Commit', 'Not a Git repository.');
      return;
    }
    setState(() => _gitBusy = true);
    try {
      await _gateway.commitGitChanges(message: message, files: files);
      _gitCommitController.clear();
      _selectedGitFiles.clear();
      _selectedGitDiffFile = null;
      _gitDiff = null;
      await _refreshGit();
      _appendLog('[info] Git commit created');
    } catch (error) {
      await _showError('Commit', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitCheckout(String branch) async {
    setState(() => _gitBusy = true);
    try {
      await _gateway.checkoutGitBranch(branch);
      await _refreshGit();
      _appendLog('[info] Checked out branch "$branch"');
    } catch (error) {
      await _showError('Checkout branch', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitCreateBranch(String name) async {
    setState(() => _gitBusy = true);
    try {
      await _gateway.createGitBranch(name);
      await _refreshGit();
      _appendLog('[info] Created branch "$name"');
    } catch (error) {
      await _showError('Create branch', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitDeleteBranch(String name) async {
    setState(() => _gitBusy = true);
    try {
      await _gateway.deleteGitBranch(name);
      await _refreshGit();
      _appendLog('[info] Deleted branch "$name"');
    } catch (error) {
      await _showError('Delete branch', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitRemote(String action, Future<GitRemoteResultInfo> Function() call) async {
    setState(() => _gitBusy = true);
    try {
      final result = await call();
      if (!mounted) return;
      if (result.success) {
        await _refreshGit();
        _appendLog('[info] Git $action completed');
      } else {
        await _showError('Git $action', result.message);
      }
    } catch (error) {
      await _showError('Git $action', error);
    } finally {
      if (mounted) setState(() => _gitBusy = false);
    }
  }

  Future<void> _handleGitSelectCommit(GitCommitInfo commit) async {
    setState(() {
      _selectedGitCommit = commit;
      _selectedGitDiffFile = null;
      _gitDiff = null;
    });
    try {
      final detail = await _gateway.getGitCommitDetail(commit.hash);
      if (!mounted) return;
      setState(() => _selectedGitCommitDetail = detail);
    } catch (error) {
      await _showError('Commit details', error);
    }
  }

  void _handleGitToggleFile(String path) {
    setState(() {
      if (_selectedGitFiles.contains(path)) {
        _selectedGitFiles.remove(path);
      } else {
        _selectedGitFiles.add(path);
      }
    });
  }

  Future<void> _handleEnablePlugin(PluginInfo plugin) async {
    try {
      final updated = await _gateway.enablePlugin(plugin.id);
      if (!mounted) return;
      setState(() => _selectedPlugin = updated);
      await _loadPlugins();
    } catch (error) {
      await showPluginErrorDialog(
        context,
        title: 'Enable Plugin',
        message: '$error',
      );
    }
  }

  Future<void> _handleDisablePlugin(PluginInfo plugin) async {
    try {
      final updated = await _gateway.disablePlugin(plugin.id);
      if (!mounted) return;
      setState(() => _selectedPlugin = updated);
      await _loadPlugins();
    } catch (error) {
      await showPluginErrorDialog(
        context,
        title: 'Disable Plugin',
        message: '$error',
      );
    }
  }

  Future<void> _handleReloadPlugin(PluginInfo plugin) async {
    try {
      final updated = await _gateway.reloadPlugin(plugin.id);
      if (!mounted) return;
      setState(() => _selectedPlugin = updated);
      await _loadPlugins();
    } catch (error) {
      await showPluginErrorDialog(
        context,
        title: 'Reload Plugin',
        message: '$error',
      );
    }
  }

  Future<void> _handleOpenPluginFolder(PluginInfo plugin) async {
    final path = plugin.path;
    if (path == null) return;
    if (Theme.of(context).platform == TargetPlatform.macOS) {
      await Process.run('open', [path]);
    } else if (Theme.of(context).platform == TargetPlatform.windows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }

  Future<void> _connectExecutionStream() => _execution.connectStream();

  void _startElapsedTimer() => _execution.startElapsedTimer();

  void _stopElapsedTimer() => _execution.stopElapsedTimer();

  Future<void> _loadExecutionHistory() => _execution.loadExecutionHistory();

  Future<void> _loadReports() => _execution.loadReports();

  Future<void> _openReports() async {
    if (!await _ensureWorkspace(message: 'Open a workspace before viewing reports.')) return;
    setState(() {
      _showReportsPage = true;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
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
      _execution.selectedReport = run;
      _showReportsPage = true;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
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
      setState(() => _execution.selectedReport = fresh);
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
      setState(() => _execution.selectedReport = null);
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
    if (!await _ensureProject(message: 'Open a project before running tests.')) return;
    if (!await _ensureEnvironment(message: 'Activate an environment before running tests.')) return;

    setState(() {
      _execution.executionLines = [];
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
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
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
    if (!await _ensureProject(message: 'Open a project before running tests.')) return;
    if (!await _ensureEnvironment(message: 'Activate an environment before running tests.')) return;

    setState(() {
      _execution.executionLines = [];
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
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
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
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
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

  Future<bool> _ensureWorkspace({
    String message = 'Open a workspace to continue.',
  }) async {
    if (_workspace.activeWorkspace != null) return true;
    if (!mounted) return false;
    await showGuidanceDialog(
      context: context,
      title: 'Workspace needed',
      message: message,
      primaryLabel: 'Open Workspace…',
      onPrimary: () => unawaited(_handleOpenWorkspace()),
      secondaryLabel: 'New Workspace…',
      onSecondary: () => unawaited(_handleNewWorkspace()),
    );
    return false;
  }

  Future<bool> _ensureProject({
    String message =
        'Select a project in the Explorer, or create one, before continuing.',
  }) async {
    if (_selectedProject != null) return true;
    if (_workspace.activeWorkspace == null) {
      return _ensureWorkspace(
        message: 'Open a workspace, then select a project to continue.',
      );
    }
    if (!mounted) return false;
    await showGuidanceDialog(
      context: context,
      title: 'Project needed',
      message: message,
      primaryLabel: 'Open Explorer',
      onPrimary: () {
        setState(() => _activePanel = SidebarPanel.explorer);
      },
      secondaryLabel: 'New Project…',
      onSecondary: () => unawaited(_handleNewProject()),
    );
    return false;
  }

  Future<bool> _ensureEnvironment({
    String message =
        'Activate a Python environment before running tests.',
  }) async {
    if (_activeEnvironment != null) return true;
    if (_workspace.activeWorkspace == null) {
      return _ensureWorkspace(
        message: 'Open a workspace, then activate an environment to continue.',
      );
    }
    if (!mounted) return false;
    await showGuidanceDialog(
      context: context,
      title: 'Environment needed',
      message: message,
      primaryLabel: 'Manage Environments…',
      onPrimary: () => unawaited(_handleManageEnvironments()),
    );
    return false;
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
        _workspace.activeWorkspace = workspace;
        _selectedProject = null;
        _selectedEnvironment = null;
        _selectedPackage = null;
        _showEnvironmentManager = false;
        _showPackageManager = false;
        _showReportsPage = false;
        _showSearchPage = false;
        _execution.selectedReport = null;
        _execution.reportRuns = [];
        _execution.reportsDashboard = null;
        _searchQuery = '';
        _searchKind = null;
        _searchResults = [];
        _selectedSymbol = null;
        _hoverInfo = null;
        _references = [];
        _navigationMessage = null;
        _activePanel = SidebarPanel.explorer;
        _editor.tabs = [];
        _editor.activePath = null;
        _editor.documentOutline = [];
        _editorHover = null;
        _editorReferences = [];
        _editor.statusMessage = null;
        _editor.jumpToLine = null;
        _editor.fileTree = [];
        _editor.recentFiles = [];
        _showEditorPage = false;
        _showSourceControl = false;
        _gitStatus = null;
        _gitBranches = [];
        _gitHistory = [];
        _selectedGitCommit = null;
        _selectedGitCommitDetail = null;
        _gitDiff = null;
        _selectedGitDiffFile = null;
        _selectedGitFiles.clear();
        _gitCommitController.clear();
        _editor.selectedOutlineSymbol = null;
        _busy = false;
      });
      _appendLog('[info] $successMessage "${workspace.name}"');
      await _loadRecent();
      await _loadProjects();
      await _maybeAutoSelectProject();
      await _loadEnvironments();
      await _loadExecutionHistory();
      await _loadIndexStatus();
      await _editor.loadFileTree();
      await _loadGitStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Workspace error', error);
    }
  }

  Future<void> _handleNewProject() async {
    if (!await _ensureWorkspace(message: 'Open a workspace before creating a project.')) return;
    final result = await showNewProjectDialog(context);
    if (result == null) return;
    await _runProjectAction(
      () => _gateway.createProject(name: result.name, type: result.type),
      successMessage: 'Created project',
    );
  }

  Future<void> _handleImportProject() async {
    if (!await _ensureWorkspace(message: 'Open a workspace before importing a project.')) return;
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

  Future<void> _maybeAutoSelectProject() async {
    if (_selectedProject != null || _projects.isEmpty) return;
    final workspaceId = _activeWorkspace?.id;
    if (workspaceId == null) return;
    final recentMatch = _recentProjects
        .where((item) => item.workspaceId == workspaceId)
        .toList();
    final pick = recentMatch.isNotEmpty ? recentMatch.first : _projects.first;
    await _handleSelectProject(pick);
  }

  Future<void> _revealExecutionLogs() async {
    setState(() {
      _showExecutionPage = true;
      _revealExecutionLogsToken++;
    });
  }

  Future<void> _handleOpenRecentProject(ProjectInfo project) async {
    final needsWorkspace = _workspace.activeWorkspace == null ||
        _activeWorkspace!.id != project.workspaceId;
    if (needsWorkspace) {
      final matches = _recentWorkspaces
          .where((item) => item.id == project.workspaceId)
          .toList();
      if (matches.isEmpty) {
        if (!mounted) return;
        await showGuidanceDialog(
          context: context,
          title: 'Workspace needed',
          message:
              'This project belongs to a workspace that is not in Recent Workspaces. Open the workspace folder, then try again.',
          primaryLabel: 'Open Workspace…',
          onPrimary: () => unawaited(_handleOpenWorkspace()),
        );
        return;
      }
      await _runWorkspaceAction(
        () => _gateway.openWorkspace(matches.first.path),
        successMessage: 'Opened workspace',
      );
      if (!mounted ||
          _workspace.activeWorkspace == null ||
          _activeWorkspace!.id != project.workspaceId) {
        return;
      }
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
    if (!await _ensureWorkspace(message: 'Open a workspace before managing environments.')) return;
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
    if (!await _ensureWorkspace(message: 'Open a workspace before managing packages.')) return;
    setState(() {
      _showPackageManager = true;
      _showSourceControl = false;
      _showPluginManager = false;
      _showReportsPage = false;
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
    if (!await _ensureWorkspace(message: 'Open a workspace before creating an environment.')) return;
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
    if (!await _ensureWorkspace(message: 'Open a workspace before importing an environment.')) return;
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

  Future<void> _handleRunFinished() async {
    await _loadExecutionHistory();
    if (!mounted) return;
    await _suggestMissingLibraryInstall();
  }

  Future<void> _suggestMissingLibraryInstall() async {
    final suggestion = _missingLibrarySuggestion(_executionLines);
    if (suggestion == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Missing library "${suggestion.library}". Install ${suggestion.package}?',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Install',
          onPressed: () {
            unawaited(_installSuggestedPackage(suggestion.package));
          },
        ),
      ),
    );
  }

  Future<void> _installSuggestedPackage(String packageName) async {
    try {
      await _handleOpenPackageManager();
      if (!mounted) return;
      setState(() => _busy = true);
      await _gateway.installPackage(packageName);
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[info] Installed $packageName');
      await _loadPackages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Installed $packageName'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] Install failed: $error');
      await _showError('Install package', error);
    }
  }

  static ({String library, String package})? _missingLibrarySuggestion(
    List<String> lines,
  ) {
    const packagesByLibrary = {
      'Browser': 'robotframework-browser',
      'SeleniumLibrary': 'robotframework-seleniumlibrary',
      'RequestsLibrary': 'robotframework-requests',
      'AppiumLibrary': 'robotframework-appiumlibrary',
    };
    final joined = lines.join('\n');
    final match = RegExp(
      "(?:No module named|Importing library) ['\"](\\w+)['\"]",
    ).firstMatch(joined);
    if (match == null) return null;
    final library = match.group(1)!;
    final package = packagesByLibrary[library];
    if (package == null) return null;
    return (library: library, package: package);
  }

  Future<void> _loadTestSuites() async {
    if (_workspace.activeWorkspace == null || !_workspace.backendConnected) {
      if (!mounted) return;
      setState(() => _testSuites = []);
      return;
    }
    try {
      final suites = await _gateway.searchSymbols(
        query: '',
        kind: SymbolKind.testSuite,
      );
      if (!mounted) return;
      setState(() => _testSuites = suites);
    } catch (error) {
      _appendLog('[warn] Could not load test suites: $error');
    }
  }

  void _trackRecentFile(String path) => _editor.trackRecentFile(path);

  Future<void> _openFile(String path, {int? line}) async {
    AppLogger.info(
      'Open file',
      tag: 'Shell',
      data: 'path=$path line=$line',
    );
    if (!await _ensureWorkspace(message: 'Open a workspace before editing files.')) return;

    final existingIndex =
        _editorTabs.indexWhere((tab) => tab.path == path);
    if (existingIndex >= 0) {
      AppLogger.debug('Reusing open tab', tag: 'Shell', data: path);
      setState(() {
        _editor.activePath = path;
        _showEditorPage = true;
        _editor.jumpToLine = line;
        _editorHover = null;
        _editorReferences = [];
        _editor.statusMessage = null;
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
        _editor.tabs = [
          ..._editorTabs,
          EditorTabInfo(
            path: file.path,
            content: file.content,
            savedContent: file.content,
            mtime: file.mtime,
          ),
        ];
        _editor.activePath = file.path;
        _showEditorPage = true;
        _editor.jumpToLine = line;
        _editorHover = null;
        _editorReferences = [];
        _editor.statusMessage = null;
        _busy = false;
      });
      _trackRecentFile(file.path);
      await _loadOutline(file.path);
      unawaited(_refreshLanguageFeatures());
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
      _editor.tabs = updated;
      if (_editor.activePath == path) {
        if (updated.isEmpty) {
          _editor.activePath = null;
          _editor.documentOutline = [];
          _editor.selectedOutlineSymbol = null;
          _showEditorPage = false;
        } else {
          nextPath = updated.last.path;
          _editor.activePath = nextPath;
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
    if (_editor.activePath == path) {
      await _checkExternalChanges(path);
      return;
    }

    setState(() {
      _editor.activePath = path;
      _showEditorPage = true;
      _editor.jumpToLine = null;
      _editorHover = null;
      _editorReferences = [];
      _editor.statusMessage = null;
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

  void _onContentChanged(String path, String content) =>
      _editor.onContentChanged(path, content);

  void _scheduleLanguageRefresh() => _editor.scheduleLanguageRefresh();

  Future<void> _refreshLanguageFeatures() => _editor.refreshLanguageFeatures();

  Future<void> _refreshWorkspaceProblems() => _editor.refreshWorkspaceProblems();

  EditorBreadcrumbInfo _buildBreadcrumb() {
    final tab = _activeEditorTab;
    if (tab == null) {
      return const EditorBreadcrumbInfo();
    }
    final normalized = tab.path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    final fileName = parts.isNotEmpty ? parts.last : tab.path;
    String? folder;
    String? project;
    if (parts.length >= 2) {
      folder = parts[parts.length - 2];
    }
    final projectsIndex = parts.indexOf('Projects');
    if (projectsIndex >= 0 && projectsIndex + 1 < parts.length) {
      project = parts[projectsIndex + 1];
    }
    IndexedSymbolInfo? symbol;
    for (final item in _documentOutline.reversed) {
      if (item.line <= _cursorLine &&
          (item.kind == SymbolKind.keyword ||
              item.kind == SymbolKind.testCase)) {
        symbol = item;
        break;
      }
    }
    return EditorBreadcrumbInfo(
      workspace: _activeWorkspace?.name,
      project: project,
      folder: folder,
      fileName: fileName,
      symbol: symbol,
    );
  }

  Future<void> _editorFormatDocument() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    try {
      final formatted = await _gateway.languageFormat(
        filePath: tab.path,
        content: tab.content,
      );
      if (!mounted) return;
      setState(() {
        tab.content = formatted;
        _editor.statusMessage = 'Formatted document';
      });
      _scheduleLanguageRefresh();
    } catch (error) {
      await _showError('Format Document', error);
    }
  }

  Future<void> _editorFormatSelection() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final start = tab.cursorLine ?? _cursorLine;
    final end = tab.cursorLine ?? _cursorLine;
    try {
      final formatted = await _gateway.languageFormat(
        filePath: tab.path,
        content: tab.content,
        startLine: start,
        endLine: end,
      );
      if (!mounted) return;
      setState(() {
        tab.content = formatted;
        _editor.statusMessage = 'Formatted selection';
      });
      _scheduleLanguageRefresh();
    } catch (error) {
      await _showError('Format Selection', error);
    }
  }

  Future<void> _editorPeekDefinition() async {
    final token = _editorTokenName();
    if (token == null) return;
    try {
      final definition = await _gateway.languageDefinition(name: token);
      if (!mounted) return;
      setState(() => _editor.peekDefinition = definition);
    } catch (error) {
      await _showError('Peek Definition', error);
    }
  }

  Future<void> _editorCtrlClickDefinition() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final token = _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
    if (token == null) return;
    try {
      final definition = await _gateway.languageDefinition(
        name: token,
        filePath: tab.path,
        line: _cursorLine,
        column: _cursorColumn,
        content: tab.content,
      );
      if (!mounted) return;
      if (definition != null) {
        await _openFile(definition.filePath, line: definition.line);
      }
    } catch (error) {
      await _showError('Go to Definition', error);
    }
  }

  Future<void> _editorOpenSymbol() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final queryController = TextEditingController();
    final selected = await showDialog<IndexedSymbolInfo>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Open Symbol'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: queryController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Filter symbols in file'),
              onSubmitted: (_) {},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final symbols = await _gateway.documentSymbols(tab.path);
                if (!context.mounted) return;
                final query = queryController.text.trim().toLowerCase();
                final filtered = symbols
                    .where((item) =>
                        query.isEmpty ||
                        item.name.toLowerCase().contains(query))
                    .toList();
                if (filtered.isEmpty) return;
                Navigator.of(context).pop(filtered.first);
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    setState(() => _editor.jumpToLine = selected.line);
  }

  Future<void> _editorWorkspaceSymbol() async {
    final queryController = TextEditingController();
    final selected = await showDialog<IndexedSymbolInfo>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Workspace Symbol'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: queryController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search workspace symbols'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final symbols = await _gateway.workspaceSymbols(
                  query: queryController.text.trim(),
                );
                if (!context.mounted) return;
                if (symbols.isEmpty) return;
                Navigator.of(context).pop(symbols.first);
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    await _openFile(selected.filePath, line: selected.line);
  }

  void _handleProblemSelected(DiagnosticInfo diagnostic) {
    unawaited(_openFile(diagnostic.filePath, line: diagnostic.line));
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
        _editor.statusMessage = 'Saved ${_fileNameFromPath(path)}';
      });
      _appendLog('[info] Saved "$path"');
      await _loadGitStatus();
    } catch (error) {
      _appendLog('[error] Save failed: $error');
      await _showError('Save file', error);
    }
  }

  Future<void> _loadOutline(String path) async {
    await _editor.loadOutline(path);
  }

  String? _extractWordAtCursor(String content, int line, int column) =>
      EditorShellController.extractWordAtCursor(content, line, column);

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
        _editor.statusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editor.statusMessage = null;
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
          _editor.statusMessage = 'No definition found for "$token".';
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
        _editor.statusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editor.statusMessage = null;
      _editorReferences = [];
      _editorHover = null;
    });

    try {
      final refs = await _gateway.languageReferences(name: token);
      if (!mounted) return;
      setState(() {
        _editorReferences = refs;
        if (refs.isEmpty) {
          _editor.statusMessage = 'No references found for "$token".';
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
        _editor.statusMessage = 'Place the cursor on a symbol or select one in the outline.';
      });
      return;
    }

    setState(() {
      _editor.statusMessage = null;
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final hover = await _gateway.languageHover(name: token);
      if (!mounted) return;
      setState(() {
        _editorHover = hover;
        if (hover == null) {
          _editor.statusMessage = 'No hover info for "$token".';
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
      _editor.statusMessage = 'Path: $path (copied to clipboard)';
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
    if (!await _ensureWorkspace(message: 'Open a workspace before searching symbols.')) return;
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
      _execution.selectedReport = null;
      if (kind != null) {
        _searchKind = kind;
      }
    });
    _loadIndexStatus();
  }

  Future<void> _loadIndexStatus() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
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
    if (_workspace.activeWorkspace == null) return;
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
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') return;

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
    if (_workspace.activeWorkspace == null) return _CenterView.welcome;
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
    if (_showPluginManager || _activePanel == SidebarPanel.plugins) {
      return _CenterView.plugins;
    }
    if (_showSourceControl || _activePanel == SidebarPanel.sourceControl) {
      return _CenterView.sourceControl;
    }
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
    final connected = _workspace.backendStatus == 'connected';
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
                onRun: _handleRunFile,
                onRunProject: _handleRunProject,
                onStop: _handleStopExecution,
                isExecutionRunning: _executionStatus.isActive,
                executionStatusLabel: _executionStatus.label,
                executionElapsedLabel: _elapsedLabel,
                onExecutionStatusTap: _revealExecutionLogs,
                canRun: _selectedProject != null,
                canRunProject: _selectedProject != null,
                onOpenWorkspace: _handleOpenWorkspace,
                onNewWorkspace: _handleNewWorkspace,
                onOpenSearch: () => _openSearchPanel(),
                gitBranchLabel: _gitStatus?.repository.branch,
                gitBranches: _gitBranchNames,
                onGitBranchSelected: _handleGitCheckout,
                onGitCreateBranch: _handleGitCreateBranch,
                onGitDeleteBranch: _handleGitDeleteBranch,
                onGitFetch: () => _handleGitRemote('fetch', _gateway.fetchGit),
                onGitPull: () => _handleGitRemote('pull', _gateway.pullGit),
                onGitPush: () => _handleGitRemote('push', _gateway.pushGit),
                showGitRemoteActions:
                    _gitStatus?.repository.isRepository == true,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSidebar(
                      activePanel: _activePanel,
                      onSettings: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Settings is coming in a later milestone.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
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
                            _execution.selectedReport = null;
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
                                panel == SidebarPanel.plugins ||
                                panel == SidebarPanel.reports) {
                              _showEditorPage = false;
                            }
                          }
                        });
                        if (panel == SidebarPanel.packages) {
                          _handleOpenPackageManager();
                        } else if (panel == SidebarPanel.plugins) {
                          _handleOpenPluginManager();
                        } else if (panel == SidebarPanel.sourceControl) {
                          _handleOpenSourceControl();
                        } else if (panel == SidebarPanel.reports) {
                          _openReports();
                        } else if (panel == SidebarPanel.tests) {
                          _loadExecutionHistory();
                          _loadTestSuites();
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
                      recentRuns: _reportRuns.take(8).toList(),
                      onSelectReport: _selectReport,
                      onOpenReports: _openReports,
                      testSuites: _testSuites,
                      onSelectTestSuite: (suite) {
                        unawaited(_openFile(suite.filePath, line: suite.line));
                      },
                      fileTree: _fileTree,
                      onOpenFile: _openFile,
                      gitFileStatuses: _gitFileStatuses,
                    ),
                    Expanded(child: _buildCenter()),
                  ],
                ),
              ),
              BottomPanel(
                logLines: _logLines,
                executionLines: _executionLines,
                problems: _workspaceProblems,
                isLoadingProblems: _loadingLanguageFeatures,
                problemCount: _workspaceProblems.length,
                forceExecutionTab: _executionStatus.isActive,
                revealExecutionLogsToken: _revealExecutionLogsToken,
                onProblemSelected: _handleProblemSelected,
              ),
              StatusBar(
                backendConnected: connected,
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
                errorCount: _workspaceProblems
                    .where((item) => item.severity == DiagnosticSeverity.error)
                    .length,
                warningCount: _workspaceProblems
                    .where((item) => item.severity == DiagnosticSeverity.warning)
                    .length,
                robotVersion: _activeEnvironment?.robotVersion,
                pythonVersion: _activeEnvironment?.pythonVersion,
                venvName: _activeEnvironment?.name,
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
          onNewProject: null,
          onImportProject: null,
          onManageEnvironments: null,
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
          onOpenRecentFile: _workspace.activeWorkspace == null ? null : _openFile,
          onContinueWorking:
              _workspace.activeWorkspace == null ? null : _handleContinueWorking,
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
      _CenterView.plugins => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PluginManagerPage(
                plugins: _plugins,
                isLoading: _loadingPlugins,
                selected: _selectedPlugin,
                onRefresh: () => _loadPlugins(refresh: true),
                onSelect: (plugin) => setState(() => _selectedPlugin = plugin),
                onEnable: _handleEnablePlugin,
                onDisable: _handleDisablePlugin,
                onReload: _handleReloadPlugin,
                onOpenFolder: _handleOpenPluginFolder,
              ),
            ),
            PluginDetailsPanel(
              plugin: _selectedPlugin,
              onEnable: _selectedPlugin == null
                  ? () {}
                  : () => _handleEnablePlugin(_selectedPlugin!),
              onDisable: _selectedPlugin == null
                  ? () {}
                  : () => _handleDisablePlugin(_selectedPlugin!),
              onReload: _selectedPlugin == null
                  ? () {}
                  : () => _handleReloadPlugin(_selectedPlugin!),
            ),
          ],
        ),
      _CenterView.sourceControl => SourceControlPage(
          status: _gitStatus,
          branches: _gitBranches,
          history: _gitHistory,
          selectedCommit: _selectedGitCommit,
          commitDetail: _selectedGitCommitDetail,
          diff: _gitDiff,
          selectedFiles: _selectedGitFiles,
          selectedDiffFile: _selectedGitDiffFile,
          commitController: _gitCommitController,
          isLoading: _loadingGit,
          isBusy: _gitBusy,
          isLoadingHistory: _loadingGitHistory,
          isLoadingDiff: _loadingGitDiff,
          onRefresh: _refreshGit,
          onInit: _handleGitInit,
          onToggleFile: _handleGitToggleFile,
          onSelectDiffFile: _loadGitDiff,
          onCommitAll: () => _handleGitCommit(),
          onCommitSelected: () =>
              _handleGitCommit(files: _selectedGitFiles.toList()),
          onSelectCommit: _handleGitSelectCommit,
          onRefreshHistory: _loadGitHistory,
          onFetch: () => _handleGitRemote('fetch', _gateway.fetchGit),
          onPull: () => _handleGitRemote('pull', _gateway.pullGit),
          onPush: () => _handleGitRemote('push', _gateway.pushGit),
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
          breadcrumb: _buildBreadcrumb(),
          completionItems: _completionItems,
          diagnostics: _editorDiagnostics,
          signatureHelp: _signatureHelp,
          peekDefinition: _peekDefinition,
          jumpToLine: _jumpToLine,
          onSelectTab: _selectTab,
          onCloseTab: _closeTab,
          onContentChanged: _onContentChanged,
          onSave: _saveActive,
          onSaveAll: _saveAll,
          onToggleWordWrap: () => setState(
            () => _editor.wordWrap = !_editor.wordWrap,
          ),
          onGoToDefinition: _editorGoToDefinition,
          onPeekDefinition: _editorPeekDefinition,
          onFindReferences: _editorFindReferences,
          onHover: _editorHoverLookup,
          onFormatDocument: _editorFormatDocument,
          onFormatSelection: _editorFormatSelection,
          onOpenSymbol: _editorOpenSymbol,
          onWorkspaceSymbol: _editorWorkspaceSymbol,
          onCtrlClick: _editorCtrlClickDefinition,
          onClosePeek: () => setState(() => _editor.peekDefinition = null),
          onOutlineSelect: (symbol) {
            setState(() {
              _editor.selectedOutlineSymbol = symbol;
              _editor.jumpToLine = symbol.line;
            });
          },
          onFind: () {},
          onReplace: () {},
          onReveal: _revealCurrentFile,
          onCursorChanged: _editor.onCursorChanged,
        ),
      _CenterView.placeholder => _WorkspaceOpenPlaceholder(
          workspace: _activeWorkspace!,
          projects: _projects,
          onSelectProject: _handleSelectProject,
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
    required this.projects,
    required this.onSelectProject,
    required this.onNewProject,
    required this.onImportProject,
    required this.onManageEnvironments,
  });

  final WorkspaceInfo workspace;
  final List<ProjectInfo> projects;
  final ValueChanged<ProjectInfo> onSelectProject;
  final VoidCallback onNewProject;
  final VoidCallback onImportProject;
  final VoidCallback onManageEnvironments;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
              projects.isEmpty
                  ? 'Create a project to get started.'
                  : 'Continue with a project from this workspace.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (projects.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final project in projects.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => onSelectProject(project),
                      icon: const Icon(Icons.play_arrow_outlined, size: 16),
                      label: Text('Continue with ${project.name}'),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
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
      ),
    );
  }
}
