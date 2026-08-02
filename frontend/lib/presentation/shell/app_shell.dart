import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gateway/models/workspace_event_info.dart';
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
import '../environment/python_install_guidance.dart';
import '../editor/editor_page.dart';
import '../editor/editor_tabs_bar.dart';
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
import '../doctor/doctor_page.dart';
import '../reports/delete_run_dialog.dart';
import '../reports/reports_page.dart';
import '../search/command_palette.dart';
import '../search/search_page.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/sidebar_panel.dart';
import '../toolbar/app_toolbar.dart';
import 'app_menu_bar.dart';
import 'shell_shortcuts.dart';
import '../widgets/side_panel_resize_handle.dart';
import '../widgets/environment_prompt_toast.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_dialog.dart';
import '../widgets/guidance_dialog.dart';
import '../widgets/virtual_file_tree.dart';
import '../workspace/explorer_file_actions.dart';
import '../workspace/new_workspace_dialog.dart';
import '../workspace/welcome_screen.dart';
import 'controllers/editor_shell_controller.dart';
import 'controllers/execution_shell_controller.dart';
import 'controllers/workspace_live_controller.dart';
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
  doctor,
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
  late final WorkspaceLiveController _live;
  String? _liveNotification;
  String? _progressOverlay;
  bool _missingProjectDialogOpen = false;
  bool _missingWorkspaceDialogOpen = false;
  final GlobalKey<VirtualFileTreeState> _fileTreeKey =
      GlobalKey<VirtualFileTreeState>();
  final GlobalKey<EditorPageState> _editorPageKey =
      GlobalKey<EditorPageState>();

  void _notify() {
    if (mounted) setState(() {});
  }

  void _appendLog(String line) => _workspace.append(line);
  bool _showEnvironmentManager = false;
  double _sidePanelWidth = SidePanel.defaultWidth;
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
  String? _envPromptTitle;
  String? _envPromptMessage;
  List<EnvironmentPromptAction>? _envPromptActions;

  ProjectInfo? _selectedProject;
  EnvironmentInfo? _selectedEnvironment;
  bool _showExecutionPage = false;
  int _toggleTerminalToken = 0;
  int _revealProblemsToken = 0;
  bool _sidePanelCollapsed = false;
  final List<String> _recentlyClosedPaths = [];
  bool _showReportsPage = false;
  bool _showDoctorPage = false;
  String _searchQuery = '';
  SymbolKind? _searchKind;
  List<IndexedSymbolInfo> _searchResults = [];
  List<IndexedSymbolInfo> _testSuites = [];
  TestNodeInfo? _testTree;
  bool _loadingTestTree = false;
  String _testFilter = '';
  Timer? _testFilterDebounce;
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

  /// Toolbar project chip — name only (branch/env have their own controls).
  String get _chromeContextLabel {
    final project = _selectedProject;
    if (project != null) return project.name;
    if (_projects.length > 1) {
      return _activeWorkspace?.name ?? 'No project';
    }
    return 'No project';
  }

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
  int? get _jumpToColumn => _editor.jumpToColumn;
  int get _cursorLine => _editor.cursorLine;
  int get _cursorColumn => _editor.cursorColumn;
  List<String> get _recentFiles => _editor.recentFiles;
  IndexedSymbolInfo? get _selectedOutlineSymbol =>
      _editor.selectedOutlineSymbol;
  List<CompletionItemInfo> get _completionItems => _editor.completionItems;
  List<DiagnosticInfo> get _editorDiagnostics => _editor.diagnostics;
  List<DiagnosticInfo> get _workspaceProblems => _editor.workspaceProblems;
  SignatureHelpInfo? get _hoverTooltip => _editor.hoverTooltip;
  IndexedSymbolInfo? get _peekDefinition => _editor.peekDefinition;

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
    _live = WorkspaceLiveController(
      notify: _notify,
      isMounted: () => mounted,
      appendLog: _appendLog,
      onFilesystemEvent: _handleLiveFilesystemEvent,
      onGitChanged: _refreshGit,
      onIndexUpdated: _handleLiveIndexUpdated,
      onTestsChanged: () => _loadTestTree(),
      onEnvironmentChanged: _loadEnvironments,
      onProjectMissing: _handleLiveProjectMissing,
      onWorkspaceMissing: _handleLiveWorkspaceMissing,
      onStatusMessage: (message) {
        if (!mounted) return;
        setState(() {
          _liveNotification = message.isEmpty ? null : message;
          final lower = message.toLowerCase();
          final isProgress = lower.contains('indexing') ||
              lower.contains('analyzing');
          if (message.isEmpty ||
              lower.contains('synchronized') ||
              lower.contains('removed')) {
            _progressOverlay = null;
          } else if (isProgress) {
            _progressOverlay = message;
          }
        });
      },
      onProgressBusy: (busy) {
        if (!mounted) return;
        if (!busy) {
          setState(() => _progressOverlay = null);
        }
      },
    );
    AppLogger.info('AppShell init', tag: 'Shell');
    _bootstrap();
  }

  @override
  void dispose() {
    AppLogger.debug('AppShell dispose', tag: 'Shell');
    _testFilterDebounce?.cancel();
    _gitCommitController.dispose();
    _live.dispose();
    _workspace.dispose();
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
    await _workspace.startBackendMonitoring(
      onConnected: () async {
        _connectExecutionStream();
        unawaited(_live.connect());
        await _loadRecent();
      },
      onDisconnected: () async {
        await _execution.disconnectStream();
        await _live.disconnect();
      },
    );
    if (_backendStatus != 'connected') {
      await _loadRecent();
    }
    AppLogger.debug(
      'Bootstrap done',
      tag: 'Shell',
      data: 'backend=$_backendStatus',
    );
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
        final projectPaths = {
          for (final project in projects) project.path.replaceAll('\\', '/'),
        };
        // In-project opens must not also appear under Advanced → Recent Workspaces.
        _workspace.recentWorkspaces = workspaces
            .where(
              (workspace) =>
                  !projectPaths.contains(workspace.path.replaceAll('\\', '/')),
            )
            .toList();
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
          final match = plugins
              .where((item) => item.id == _selectedPlugin!.id)
              .toList();
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
    if (!await _ensureWorkspace(
      message: 'Open a project before managing plugins.',
    )) {
      return;
    }
    setState(() {
      _showPluginManager = true;
      _showSourceControl = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
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

  List<String> get _gitBranchNames => _gitBranches
      .where((branch) => !branch.remote)
      .map((b) => b.name)
      .toList();

  Future<void> _loadGitStatus() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      setState(() {
        _gitStatus = null;
        _gitBranches = [];
        _loadingGit = false;
      });
      return;
    }

    // Only show the page skeleton on first load — keep content on refresh.
    final initialLoad = _gitStatus == null;
    if (initialLoad) {
      setState(() => _loadingGit = true);
    }
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
    final initialLoad = _gitHistory.isEmpty;
    if (initialLoad) {
      setState(() => _loadingGitHistory = true);
    }
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
    if (!await _ensureWorkspace(
      message: 'Open a project before using source control.',
    )) {
      return;
    }
    setState(() {
      _showSourceControl = true;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
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

  Future<void> _handleGitRemote(
    String action,
    Future<GitRemoteResultInfo> Function() call,
  ) async {
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
    if (!await _ensureWorkspace(
      message: 'Open a project before viewing reports.',
    )) {
      return;
    }
    setState(() {
      _showReportsPage = true;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.reports;
      _clearExecutionPageUnlessTests();
    });
    await _loadReports();
    if (!mounted) return;
    if (_selectedReport == null && _reportRuns.isNotEmpty) {
      await _selectReport(_reportRuns.first);
    }
  }

  Future<void> _openDoctor() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before running Robot Doctor.',
    )) {
      return;
    }
    setState(() {
      _showDoctorPage = true;
      _showReportsPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _execution.selectedReport = null;
      _activePanel = SidebarPanel.doctor;
      _clearExecutionPageUnlessTests();
    });
  }

  Future<void> _selectReport(ExecutionInfo run) async {
    setState(() {
      _execution.selectedReport = run;
      _showReportsPage = true;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
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
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Opened log.html',
        icon: Icons.description_outlined,
        duration: const Duration(seconds: 2),
      );
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
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Opened report.html',
        icon: Icons.description_outlined,
        duration: const Duration(seconds: 2),
      );
    } catch (error) {
      if (!mounted) return;
      await _showError('Open report', error);
    }
  }

  Future<void> _openReportXml() async {
    final run = _selectedReport;
    if (run == null) return;
    try {
      await _gateway.openReportXml(run.id);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Opened output.xml',
        icon: Icons.description_outlined,
        duration: const Duration(seconds: 2),
      );
    } catch (error) {
      if (!mounted) return;
      await _showError('Open output.xml', error);
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
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }

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
      await _handleExecutionError(error);
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
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }

    setState(() {
      _execution.executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();

    try {
      final run = await _runWithLargeRunGuard(
        start: ({required bool confirm}) =>
            _gateway.runProject(confirm: confirm),
        projectWide: true,
      );
      if (run == null) return;
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
      await _handleExecutionError(error);
    }
  }

  Future<void> _handleStopExecution() async {
    try {
      final run = await _gateway.stopExecution();
      if (!mounted) return;
      if (run.id.isEmpty) {
        setState(() {
          _execution.executionStatus = ExecutionStatus.idle;
        });
        _stopElapsedTimer();
        return;
      }
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
    await showFriendlyErrorDialog(context: context, title: title, error: error);
  }

  Future<bool> _ensureWorkspace({
    String message = 'Open a project to continue.',
  }) async {
    if (_workspace.activeWorkspace != null) return true;
    if (!mounted) return false;
    await showGuidanceDialog(
      context: context,
      title: 'Project needed',
      message: message,
      primaryLabel: 'Open Project…',
      onPrimary: () => unawaited(_handleOpenProject()),
      secondaryLabel: 'New Project…',
      onSecondary: () => unawaited(_handleNewStandaloneProject()),
    );
    return false;
  }

  Future<bool> _ensureProject({
    String message =
        'Select a project in the Explorer, or create one, before continuing.',
  }) async {
    if (_selectedProject != null) return true;
    if (_workspace.activeWorkspace == null) {
      return _ensureWorkspace(message: 'Open a project to continue.');
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
      onSecondary: () => unawaited(_handleNewStandaloneProject()),
    );
    return false;
  }

  Future<bool> _ensureEnvironment({
    String message = 'Activate a Python environment before running tests.',
  }) async {
    final env = _activeEnvironment;
    if (env != null && env.available) return true;
    if (env != null && !env.available) {
      if (!mounted) return false;
      await showGuidanceDialog(
        context: context,
        title: 'Environment missing on disk',
        message:
            'The active environment "${env.name}" is no longer available. '
            'Recreate it or select another environment before running tests.',
        primaryLabel: 'Manage Environments…',
        onPrimary: () => unawaited(_handleManageEnvironments()),
      );
      return false;
    }
    if (_workspace.activeWorkspace == null) {
      return _ensureWorkspace(
        message: 'Open a project, then activate an environment to continue.',
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

  Future<bool> _ensureRobotReady() async {
    if (!await _ensureEnvironment(
      message: 'Activate an environment before running tests.',
    )) {
      return false;
    }
    final env = _activeEnvironment;
    final installed = _robotFrameworkInstalled ||
        (env?.robotVersion != null && env!.robotVersion!.isNotEmpty);
    if (installed) return true;
    if (!mounted) return false;
    await showGuidanceDialog(
      context: context,
      title: 'Robot Framework required',
      message:
          'Robot Framework is not installed in the active environment '
          '"${env?.name ?? 'unknown'}".\n\n'
          'Install it into this environment, or choose another interpreter '
          'that already has Robot Framework. Tests will not start until '
          'Robot is available — no empty run will be created.',
      primaryLabel: 'Install Robot Framework',
      onPrimary: () => unawaited(_handleInstallRobot()),
      secondaryLabel: 'Choose Environment…',
      onSecondary: () => unawaited(_handleManageEnvironments()),
    );
    return false;
  }

  static const int _defaultLargeRunThreshold = 100;

  Future<bool> _showLargeRunConfirmDialog({
    required int count,
    required int threshold,
    String? tag,
  }) async {
    if (!mounted) return false;
    final estimate = count > 0 ? '$count' : 'many';
    final focus = tag == null || tag.isEmpty
        ? 'the whole project'
        : 'tag filter "$tag"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Run a large test set?'),
        content: Text(
          'About to run $estimate tests for $focus '
          '(confirmation threshold: $threshold).\n\n'
          'Large runs can take a long time and make the IDE feel busy. '
          'Continue only if that is what you intended.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Run tests'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Pre-confirm when over threshold, then call [start] with confirm flags.
  /// Retries once if the backend returns 409 large_run_confirmation_required.
  Future<ExecutionInfo?> _runWithLargeRunGuard({
    required Future<ExecutionInfo> Function({required bool confirm}) start,
    String? tag,
    bool projectWide = true,
  }) async {
    int count = 0;
    try {
      count = await _gateway.countTests(tag: tag, projectWide: projectWide);
    } catch (_) {}
    final wildcard = tag != null &&
        (tag.contains('*') ||
            tag.contains('?') ||
            tag.toUpperCase().contains('OR') ||
            tag.toUpperCase().contains('AND') ||
            tag.toUpperCase().contains('NOT'));
    final needsConfirm =
        count > _defaultLargeRunThreshold || wildcard;
    if (needsConfirm &&
        !await _showLargeRunConfirmDialog(
          count: count,
          threshold: _defaultLargeRunThreshold,
          tag: tag,
        )) {
      return null;
    }
    try {
      return await start(confirm: needsConfirm);
    } on GatewayException catch (error) {
      if (!error.isLargeRunConfirmation) rethrow;
      if (!await _showLargeRunConfirmDialog(
        count: error.count ?? count,
        threshold: error.threshold ?? _defaultLargeRunThreshold,
        tag: tag,
      )) {
        return null;
      }
      return await start(confirm: true);
    }
  }

  bool _isRobotMissingError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('robot framework is not installed') ||
        text.contains('could not verify robot framework') ||
        text.contains('robot_missing') ||
        (text.contains('robot framework') &&
            (text.contains('not installed') ||
                text.contains('not available')));
  }

  Future<void> _handleExecutionError(Object error) async {
    if (!mounted) return;
    if (_isRobotMissingError(error)) {
      await showGuidanceDialog(
        context: context,
        title: 'Robot Framework required',
        message:
            'Robot Framework is missing from the active environment, so the '
            'run was not started.\n\n'
            'Install Robot Framework or choose another environment, then press '
            'F5 again.',
        primaryLabel: 'Install Robot Framework',
        onPrimary: () => unawaited(_handleInstallRobot()),
        secondaryLabel: 'Choose Environment…',
        onSecondary: () => unawaited(_handleManageEnvironments()),
      );
      return;
    }
    await _showError('Execution error', error);
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

  Future<void> _handleOpenProject() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Open Project',
    );
    if (selected == null) return;
    await _openProjectAtPath(selected);
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
    ProjectInfo? selectedProject,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final workspace = await action();
      if (!mounted) return;
      await _applyOpenedWorkspace(
        workspace,
        successMessage: successMessage,
        selectedProject: selectedProject,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Could not open that folder', error);
    }
  }

  Future<void> _openProjectAtPath(String path, {bool force = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _gateway.openProjectByPath(path, force: force);
      if (!mounted) return;
      await _applyOpenedWorkspace(
        result.workspace,
        successMessage: 'Opened project "${result.project.name}"',
        selectedProject: result.project,
        detectedEnvironments: result.detectedEnvironments,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      if (!force && _isNonRobotProjectWarning(error)) {
        final continueAnyway = await showContinueAnywayDialog(
          context: context,
          title: 'Could not open project',
          error: error,
        );
        if (!mounted) return;
        if (continueAnyway) {
          await _openProjectAtPath(path, force: true);
        }
        return;
      }
      await _showError('Could not open project', error);
    }
  }

  bool _isNonRobotProjectWarning(Object error) {
    return error.toString().toLowerCase().contains(
      'does not look like a robot framework project',
    );
  }

  Future<void> _applyOpenedWorkspace(
    WorkspaceInfo workspace, {
    required String successMessage,
    ProjectInfo? selectedProject,
    List<DetectedEnvironmentInfo> detectedEnvironments = const [],
  }) async {
    setState(() {
      _workspace.activeWorkspace = workspace;
      _selectedProject = selectedProject;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
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
      _editor.setStatusMessage(null);
      _editor.jumpToLine = null;
      _editor.jumpToColumn = null;
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
    _appendLog(
      selectedProject == null
          ? '[info] $successMessage "${workspace.name}"'
          : '[info] $successMessage',
    );
    await _loadRecent();
    await _loadProjects();
    if (selectedProject == null) {
      await _maybeAutoSelectProject();
    } else {
      final match = _projects
          .where((item) => item.id == selectedProject.id)
          .toList();
      if (match.isNotEmpty && mounted) {
        setState(() => _selectedProject = match.first);
      }
    }
    // Fire remaining work without delaying first paint of the shell.
    unawaited(_loadExecutionHistory());
    unawaited(_loadIndexStatus());
    unawaited(_editor.loadFileTree());
    unawaited(_loadGitStatus());
    unawaited(() async {
      await _loadEnvironments();
      if (!mounted || _environments.isNotEmpty) return;
      await _showEnvironmentPrompt(detectedEnvironments);
    }());
  }

  /// Folder to prefill as the parent for a new project: sibling of whatever is
  /// currently open, else the user's home directory.
  String? _defaultNewProjectLocation() {
    final current = _selectedProject?.path ?? _activeWorkspace?.path;
    if (current != null && current.isNotEmpty) {
      return ExplorerFileActions.parentPath(current);
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return (home == null || home.isEmpty) ? null : home;
  }

  Future<void> _handleNewStandaloneProject() async {
    // Ask for name + location in one dialog. Opening a bare folder picker first
    // read as "open an existing project" instead of creating a new one.
    final created = await showNewStandaloneProjectDialog(
      context,
      initialLocation: _defaultNewProjectLocation(),
    );
    if (created == null) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final opened = await _gateway.createStandaloneProject(
        name: created.name,
        location: created.location,
      );
      if (!mounted) return;
      await _applyOpenedWorkspace(
        opened.workspace,
        successMessage: 'Created project "${opened.project.name}"',
        selectedProject: opened.project,
        detectedEnvironments: opened.detectedEnvironments,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] $error');
      await _showError('Could not create project', error);
    }
  }

  /// Adds a project to a classic multi-project container and opens it.
  ///
  /// Only reachable from the explicit "New Project in Workspace" command —
  /// every other New Project affordance creates a standalone project, because
  /// creating one while a project was open used to nest it in the current
  /// workspace and leave the Explorer on the old tree.
  Future<void> _handleNewProject() async {
    if (!await _ensureWorkspace(
      message: 'Open a workspace to add another project to it.',
    )) {
      return;
    }
    final name = await showNewProjectDialog(context);
    if (name == null) return;
    await _runProjectAction(
      () => _gateway.createProject(name: name),
      successMessage: 'Created project',
    );
  }

  Future<void> _showEnvironmentPrompt(
    List<DetectedEnvironmentInfo> detected,
  ) async {
    if (!mounted) return;
    // Prefer a bottom-right toast — MaterialBanner pushes the whole IDE chrome down.
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();

    if (detected.isNotEmpty) {
      final candidate = detected.first;
      setState(() {
        _envPromptTitle = 'Python environment found';
        _envPromptMessage =
            'Use "${candidate.name}" for this project to enable running tests.';
        _envPromptActions = [
          EnvironmentPromptAction(
            label: 'Use This Environment',
            primary: true,
            onPressed: () => unawaited(_importDetectedEnvironment(candidate)),
          ),
        ];
      });
      return;
    }

    // Probe host Python before offering Create — otherwise users hit a dead end
    // on machines with no interpreter installed.
    late final bool hasPython;
    try {
      final interpreters = await _gateway.listPythonInterpreters();
      hasPython = interpreters.isNotEmpty;
    } catch (_) {
      // Discovery failed (offline, 5xx, …) — do not pretend Python exists.
      if (!mounted) return;
      setState(() {
        _envPromptTitle = 'Could not detect Python';
        _envPromptMessage =
            'Robot Studio could not list Python interpreters. Install Python 3 '
            'if needed, start the backend if it is offline, then try creating '
            'an environment.';
        _envPromptActions = [
          EnvironmentPromptAction(
            label: 'How to Install',
            primary: true,
            onPressed: () => unawaited(_showNoPythonInstallGuide()),
          ),
          EnvironmentPromptAction(
            label: 'Create Environment',
            onPressed: () => unawaited(_createDefaultEnvironmentInBackground()),
          ),
          EnvironmentPromptAction(
            label: 'Select Existing…',
            onPressed: () => unawaited(_selectExistingEnvironment()),
          ),
        ];
      });
      return;
    }
    if (!mounted) return;

    if (!hasPython) {
      setState(() {
        _envPromptTitle = PythonInstallGuidance.toastTitle;
        _envPromptMessage = PythonInstallGuidance.toastMessage;
        _envPromptActions = [
          EnvironmentPromptAction(
            label: 'How to Install',
            primary: true,
            onPressed: () => unawaited(_showNoPythonInstallGuide()),
          ),
          EnvironmentPromptAction(
            label: 'Select Existing…',
            onPressed: () => unawaited(_selectExistingEnvironment()),
          ),
        ];
      });
      return;
    }

    setState(() {
      _envPromptTitle = 'Python environment required';
      _envPromptMessage =
          'Select an existing environment or create one to enable Robot '
          'Framework features.';
      _envPromptActions = [
        EnvironmentPromptAction(
          label: 'Create Environment',
          primary: true,
          onPressed: () => unawaited(_createDefaultEnvironmentInBackground()),
        ),
        EnvironmentPromptAction(
          label: 'Select Existing',
          onPressed: () => unawaited(_selectExistingEnvironment()),
        ),
      ];
    });
  }

  Future<void> _showNoPythonInstallGuide() async {
    if (!mounted) return;
    await showGuidanceDialog(
      context: context,
      title: 'Install Python 3',
      message: PythonInstallGuidance.detailedInstructions,
      primaryLabel: "I've Installed Python",
      onPrimary: () => unawaited(_createDefaultEnvironmentInBackground()),
      secondaryLabel: 'Select Existing…',
      onSecondary: () => unawaited(_selectExistingEnvironment()),
      dismissLabel: 'Close',
    );
  }

  void _dismissEnvironmentPrompt() {
    if (!mounted) return;
    setState(() {
      _envPromptTitle = null;
      _envPromptMessage = null;
      _envPromptActions = null;
    });
  }

  Future<void> _importDetectedEnvironment(
    DetectedEnvironmentInfo candidate,
  ) async {
    try {
      await _gateway.importEnvironment(candidate.path);
      await _loadEnvironments();
      _appendLog('[info] Using environment "${candidate.name}"');
    } catch (error) {
      _appendLog('[error] $error');
      if (mounted) await _showError('Could not use environment', error);
    }
  }

  Future<void> _createDefaultEnvironmentInBackground() async {
    _appendLog('[info] Creating Python environment in the background…');
    try {
      final interpreters = await _gateway.listPythonInterpreters();
      if (interpreters.isEmpty) {
        if (!mounted) return;
        await _showNoPythonInstallGuide();
        return;
      }
      await _gateway.createEnvironment(
        name: 'default',
        pythonInterpreter: interpreters.first.path,
        // Match Create Environment dialog default (Robot Framework on).
        installRobotFramework: true,
      );
      await _loadEnvironments();
      _dismissEnvironmentPrompt();
      _appendLog('[info] Environment "default" is ready');
    } catch (error) {
      _appendLog('[error] $error');
      if (!mounted) return;
      if (PythonInstallGuidance.matchesError(error)) {
        await _showNoPythonInstallGuide();
        return;
      }
      await _showError('Could not create environment', error);
    }
  }

  Future<void> _selectExistingEnvironment() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select an existing Python environment',
    );
    if (selected == null) return;
    try {
      await _gateway.importEnvironment(selected);
      await _loadEnvironments();
      _appendLog('[info] Imported environment from $selected');
    } catch (error) {
      _appendLog('[error] $error');
      if (mounted) await _showError('Could not import environment', error);
    }
  }

  Future<void> _handleImportProject() async {
    if (!await _ensureWorkspace(
      message: 'Open a project first, then import another project.',
    )) {
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

  Future<void> _revealTests() async {
    setState(() {
      _showExecutionPage = true;
    });
  }

  void _toggleTerminal() {
    setState(() => _toggleTerminalToken++);
  }

  void _toggleSidebar() {
    setState(() => _sidePanelCollapsed = !_sidePanelCollapsed);
  }

  void _cycleEditorTab({required bool forward}) {
    final tabs = _editorTabs;
    if (tabs.length < 2) return;
    final active = _editor.activePath;
    final index = tabs.indexWhere((tab) => tab.path == active);
    if (index < 0) return;
    final next = forward
        ? (index + 1) % tabs.length
        : (index - 1 + tabs.length) % tabs.length;
    unawaited(_selectTab(tabs[next].path));
  }

  Future<void> _reopenClosedTab() async {
    while (_recentlyClosedPaths.isNotEmpty) {
      final path = _recentlyClosedPaths.removeLast();
      if (_editorTabs.any((tab) => tab.path == path)) continue;
      await _openFile(path);
      return;
    }
  }

  Future<void> _closeActiveTab() async {
    final path = _editor.activePath;
    if (path == null) return;
    await _closeTab(path);
  }

  void _openProjectSearch() {
    setState(() {
      _activePanel = SidebarPanel.search;
      _showSearchPage = true;
      _clearExecutionPageUnlessTests();
      _showEditorPage = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
    });
  }

  Future<void> _handleOpenRecentProject(ProjectInfo project) async {
    await _openProjectAtPath(project.path);
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
    if (!await _ensureWorkspace(
      message: 'Open a project before managing environments.',
    )) {
      return;
    }
    // Keep `_selectedProject` so Run still works after creating/activating an env.
    setState(() {
      _showEnvironmentManager = true;
      _showPackageManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _clearExecutionPageUnlessTests();
    });
    await _loadEnvironments();
  }

  Future<void> _handleOpenPackageManager() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before managing packages.',
    )) {
      return;
    }
    setState(() {
      _showPackageManager = true;
      _showSourceControl = false;
      _showPluginManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showEnvironmentManager = false;
      _showSearchPage = false;
      _showEditorPage = false;
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
      operation: () =>
          _gateway.installPackage(selected.name, version: selected.version),
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
    if (!await _ensureWorkspace(
      message: 'Open a project before creating an environment.',
    )) {
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
    if (!await _ensureWorkspace(
      message: 'Open a project before importing an environment.',
    )) {
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
      () =>
          _gateway.cloneEnvironment(environmentId: environment.id, name: name),
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
    await _loadTestTree();
    if (!mounted) return;
    final latest = _executionHistory.isNotEmpty
        ? _executionHistory.first
        : null;
    if (latest != null) {
      await _selectReport(latest);
    }
    await _suggestMissingLibraryInstall();
  }

  Future<void> _suggestMissingLibraryInstall() async {
    final suggestion = _missingLibrarySuggestion(_executionLines);
    if (suggestion == null || !mounted) return;
    showAppToast(
      context,
      message:
          'Missing library "${suggestion.library}". Install ${suggestion.package}?',
      actionLabel: 'Install',
      onAction: () {
        unawaited(_installSuggestedPackage(suggestion.package));
      },
      duration: const Duration(seconds: 8),
      icon: Icons.extension_outlined,
      iconColor: AppColors.warning,
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
      showAppToast(
        context,
        message: 'Installed $packageName',
        icon: Icons.check_circle_outline,
        iconColor: AppColors.success,
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
    await _loadTestTree();
  }

  Future<void> _loadTestTree({String? query}) async {
    if (_workspace.activeWorkspace == null || !_workspace.backendConnected) {
      if (!mounted) return;
      setState(() {
        _testSuites = [];
        _testTree = null;
        _loadingTestTree = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loadingTestTree = true);
    try {
      final q = query ?? _testFilter;
      final tree = await _gateway.getTestTree(
        query: q,
        lazy: q.trim().isEmpty,
      );
      List<IndexedSymbolInfo> suites = const [];
      try {
        suites = await _gateway.searchSymbols(
          query: '',
          kind: SymbolKind.testSuite,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _testTree = tree;
        _testSuites = suites;
        _loadingTestTree = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingTestTree = false);
      _appendLog('[warn] Could not load test tree: $error');
    }
  }

  void _handleTestFilterChanged(String value) {
    setState(() => _testFilter = value);
    _testFilterDebounce?.cancel();
    _testFilterDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_loadTestTree(query: value));
    });
  }

  Future<void> _expandTestNode(TestNodeInfo node) async {
    if (node.path == null || node.path!.isEmpty) return;
    try {
      final children = await _gateway.getTestsForFile(node.path!);
      if (!mounted || _testTree == null) return;
      final refreshed = node.copyWith(children: children, detail: '');
      setState(() {
        _testTree = _testTree!.replaceChild(node.id, refreshed);
      });
    } catch (error) {
      if (!mounted) return;
      _appendLog('[warn] Could not expand suite: $error');
    }
  }

  Future<void> _handleRunTestNode(TestNodeInfo node) async {
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    setState(() {
      _execution.executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();
    try {
      final ExecutionInfo? run;
      if (node.kind == 'test' || node.kind == 'task') {
        run = await _gateway.runTest(file: node.path!, name: node.name);
      } else if (node.kind == 'suite') {
        run = await _gateway.runTestSuite(file: node.path);
      } else if (node.kind == 'project' || node.kind == 'workspace') {
        run = await _runWithLargeRunGuard(
          start: ({required bool confirm}) =>
              _gateway.runTestSuite(confirm: confirm),
          projectWide: true,
        );
        if (run == null) return;
      } else {
        return;
      }
      final started = run;
      if (started == null || !mounted) return;
      setState(() {
        _execution.executionStatus = started.status;
        _execution.currentExecution = started;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      _appendLog('[error] Test run failed: $error');
      await _handleExecutionError(error);
    }
  }

  Future<void> _handleRunAllTests() async {
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    setState(() {
      _execution.executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();
    try {
      final run = await _runWithLargeRunGuard(
        start: ({required bool confirm}) =>
            _gateway.runTestSuite(confirm: confirm),
        projectWide: true,
      );
      if (run == null) return;
      if (!mounted) return;
      setState(() {
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      await _handleExecutionError(error);
    }
  }

  Future<void> _handleRunCurrentFileTests() async {
    final path = _activeEditorPath ?? _selectedSuitePath;
    if (path == null) {
      await _handleRunFile();
      return;
    }
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    setState(() {
      _execution.executionLines = [];
      _showExecutionPage = true;
      _selectedSuitePath = path;
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runTestSuite(file: path);
      if (!mounted) return;
      setState(() {
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      await _handleExecutionError(error);
    }
  }

  Future<void> _handleRunFailedTests() async {
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    setState(() {
      _execution.executionLines = [];
      _showExecutionPage = true;
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runFailedTests();
      if (!mounted) return;
      setState(() {
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      await _handleExecutionError(error);
    }
  }

  void _handleOpenTestNode(TestNodeInfo node) {
    if (node.path == null) return;
    unawaited(_openFile(node.path!, line: node.line));
  }

  void _handleRevealTestNode(TestNodeInfo node) {
    if (node.path == null) return;
    setState(() {
      _activePanel = SidebarPanel.explorer;
      _selectedSuitePath = node.path;
    });
    unawaited(_openFile(node.path!, line: node.line));
  }

  void _trackRecentFile(String path) => _editor.trackRecentFile(path);

  Future<void> _openFile(String path, {int? line, int? column}) async {
    AppLogger.info(
      'Open file',
      tag: 'Shell',
      data: 'path=$path line=$line column=$column',
    );
    if (!await _ensureWorkspace(
      message: 'Open a project before editing files.',
    )) {
      return;
    }

    final existingIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (existingIndex >= 0) {
      AppLogger.debug('Reusing open tab', tag: 'Shell', data: path);
      setState(() {
        _editor.activePath = path;
        _showEditorPage = true;
        _editor.jumpToLine = line;
        _editor.jumpToColumn = column;
        _editorHover = null;
        _editorReferences = [];
        _editor.setStatusMessage(null);
      });
      _trackRecentFile(path);
      await _selectTab(path);
      unawaited(_refreshLanguageFeatures());
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
        _editor.jumpToColumn = column;
        _editorHover = null;
        _editorReferences = [];
        _editor.setStatusMessage(null);
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

  void _pushRecentlyClosed(String path) {
    _recentlyClosedPaths.remove(path);
    _recentlyClosedPaths.add(path);
    if (_recentlyClosedPaths.length > 20) {
      _recentlyClosedPaths.removeAt(0);
    }
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
      _pushRecentlyClosed(path);
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
      _editor.workspaceProblems = [
        for (final item in _editor.workspaceProblems)
          if (item.filePath != path) item,
      ];
      _editorHover = null;
      _editorReferences = [];
    });
    if (nextPath != null) {
      await _loadOutline(nextPath!);
    }
  }

  Future<void> _closeTabsByPaths(Iterable<String> paths) async {
    for (final path in paths.toList()) {
      if (!_editorTabs.any((tab) => tab.path == path)) continue;
      await _closeTab(path);
      // User cancelled discard for a dirty tab — stop the batch.
      if (_editorTabs.any((tab) => tab.path == path)) return;
    }
  }

  Future<void> _closeOtherTabs(String keepPath) async {
    final paths = _editorTabs
        .where((tab) => tab.path != keepPath)
        .map((tab) => tab.path)
        .toList();
    await _closeTabsByPaths(paths);
  }

  Future<void> _closeAllTabs() async {
    await _closeTabsByPaths(_editorTabs.map((tab) => tab.path).toList());
  }

  Future<void> _closeSavedTabs() async {
    final paths = _editorTabs
        .where((tab) => !tab.isDirty)
        .map((tab) => tab.path)
        .toList();
    for (final path in paths) {
      await _closeTabWithoutDirtyPrompt(path);
    }
  }

  Future<void> _closeTabsToTheRight(String path) async {
    final index = _editorTabs.indexWhere((tab) => tab.path == path);
    if (index < 0) return;
    final paths = _editorTabs.skip(index + 1).map((tab) => tab.path).toList();
    await _closeTabsByPaths(paths);
  }

  Future<void> _handleTabContextAction(
    String path,
    EditorTabContextAction action,
  ) async {
    switch (action) {
      case EditorTabContextAction.close:
        await _closeTab(path);
      case EditorTabContextAction.closeOthers:
        await _closeOtherTabs(path);
      case EditorTabContextAction.closeAll:
        await _closeAllTabs();
      case EditorTabContextAction.closeSaved:
        await _closeSavedTabs();
      case EditorTabContextAction.closeToTheRight:
        await _closeTabsToTheRight(path);
      case EditorTabContextAction.revealInOs:
        await _revealPathInOs(path);
      case EditorTabContextAction.copyRelativePath:
        await _copyRelativePath([path]);
      case EditorTabContextAction.copyAbsolutePath:
        await _copyAbsolutePath([path]);
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
      _editor.jumpToColumn = null;
      _editorHover = null;
      _editorReferences = [];
      _editor.setStatusMessage(null);
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
      await _applyExternalFileChange(tab, fresh);
    } catch (error) {
      // Missing file is handled by the deleted-open-file flow.
      final message = '$error'.toLowerCase();
      if (message.contains('not found') || message.contains('no such file')) {
        await _handleDeletedOpenFile(path);
        return;
      }
      _appendLog('[warn] Could not check external changes: $error');
    }
  }

  Future<void> _applyExternalFileChange(
    EditorTabInfo tab,
    FileContentInfo fresh,
  ) async {
    if (!tab.isDirty) {
      setState(() {
        tab.content = fresh.content;
        tab.savedContent = fresh.content;
        tab.mtime = fresh.mtime;
        if (_editor.activePath == tab.path) {
          _editor.jumpToLine = tab.cursorLine;
          _editor.jumpToColumn = tab.cursorColumn;
        }
      });
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File changed on disk'),
        content: Text('"${tab.fileName}" was modified outside the editor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Keep My Changes'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('compare'),
            child: const Text('Compare'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('reload'),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'compare') {
      showAppToast(
        context,
        message: 'Compare is coming soon',
        icon: Icons.difference_outlined,
      );
      return;
    }
    if (action == 'reload') {
      setState(() {
        tab.content = fresh.content;
        tab.savedContent = fresh.content;
        tab.mtime = fresh.mtime;
        if (_editor.activePath == tab.path) {
          _editor.jumpToLine = tab.cursorLine;
          _editor.jumpToColumn = tab.cursorColumn;
        }
      });
    }
  }

  Future<void> _handleDeletedOpenFile(String path) async {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    final tab = _editorTabs[tabIndex];

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File was deleted on disk'),
        content: Text(
          '"${tab.fileName}" no longer exists. Close the tab or restore it from the editor buffer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('close'),
            child: const Text('Close Tab'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('restore'),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'close') {
      // Force-close without discard prompt — file is already gone on disk.
      final updated = _editorTabs
          .where((item) => item.path != path)
          .toList(growable: false);
      String? nextPath;
      setState(() {
        _editor.tabs = updated.toList();
        if (_editor.activePath == path) {
          if (updated.isEmpty) {
            _editor.activePath = null;
            _showEditorPage = false;
          } else {
            nextPath = updated.last.path;
            _editor.activePath = nextPath;
          }
        }
      });
      if (nextPath != null) {
        await _loadOutline(nextPath!);
      }
      return;
    }
    if (action == 'restore') {
      try {
        final written = await _gateway.writeFile(
          path: path,
          content: tab.content,
        );
        if (!mounted) return;
        setState(() {
          tab.savedContent = tab.content;
          tab.mtime = written.mtime;
        });
      } catch (error) {
        await _showError('Could not restore file', error);
      }
    }
  }

  Future<void> _handleLiveFilesystemEvent(WorkspaceStreamEvent event) async {
    final absolute = event.absolutePath ?? event.path;
    if (absolute == null || absolute.isEmpty) return;

    switch (event.type) {
      case 'FILE_DELETED':
      case 'DIRECTORY_DELETED':
        _editor.removePathFromTree(absolute);
        if (event.type == 'FILE_DELETED') {
          final open = _editorTabs.any(
            (tab) => WorkspaceLiveController.pathsEqual(tab.path, absolute),
          );
          if (open) {
            await _handleDeletedOpenFile(absolute);
          }
        }
        if (event.oldAbsolutePath != null) {
          await _editor.refreshParentOf(event.oldAbsolutePath!);
        }
        await _editor.refreshParentOf(absolute);
        return;
      case 'FILE_RENAMED':
      case 'DIRECTORY_RENAMED':
        final oldPath = event.oldAbsolutePath ?? event.oldPath;
        if (oldPath != null) {
          _editor.removePathFromTree(oldPath);
          final tabIndex = _editorTabs.indexWhere(
            (tab) => WorkspaceLiveController.pathsEqual(tab.path, oldPath),
          );
          if (tabIndex >= 0) {
            setState(() {
              final tab = _editorTabs[tabIndex];
              final updated = EditorTabInfo(
                path: absolute,
                content: tab.content,
                savedContent: tab.savedContent,
                mtime: tab.mtime,
                cursorLine: tab.cursorLine,
                cursorColumn: tab.cursorColumn,
              );
              _editor.tabs = [
                for (var i = 0; i < _editorTabs.length; i++)
                  if (i == tabIndex) updated else _editorTabs[i],
              ];
              if (_editor.activePath == oldPath) {
                _editor.activePath = absolute;
              }
            });
          }
          await _editor.refreshParentOf(oldPath);
        }
        await _editor.refreshParentOf(absolute);
        return;
      case 'FILE_MODIFIED':
        await _editor.refreshParentOf(absolute);
        final tabIndex = _editorTabs.indexWhere(
          (tab) => WorkspaceLiveController.pathsEqual(tab.path, absolute),
        );
        if (tabIndex >= 0) {
          await _checkExternalChanges(_editorTabs[tabIndex].path);
        }
        return;
      case 'FILE_CREATED':
      case 'DIRECTORY_CREATED':
        await _editor.refreshParentOf(absolute);
        return;
      default:
        return;
    }
  }

  Future<void> _handleLiveIndexUpdated(WorkspaceStreamEvent event) async {
    await _loadIndexStatus();
    if (_showSearchPage && _searchQuery.trim().isNotEmpty) {
      await _runSearch();
    }
    final active = _activeEditorPath;
    if (active != null &&
        (active.endsWith('.robot') || active.endsWith('.resource'))) {
      await _loadOutline(active);
      _scheduleLanguageRefresh();
    }
  }

  Future<void> _handleLiveProjectMissing(WorkspaceStreamEvent event) async {
    if (_missingProjectDialogOpen || _selectedProject == null) return;
    _missingProjectDialogOpen = true;
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Project no longer exists'),
          content: const Text('The active project was removed from disk.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('dismiss'),
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('locate'),
              child: const Text('Locate'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('close'),
              child: const Text('Close Project'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'close' || action == 'locate') {
        await _unloadActiveProject();
        if (action == 'locate') {
          await _handleOpenProject();
        }
      }
    } finally {
      _missingProjectDialogOpen = false;
    }
  }

  Future<void> _handleLiveWorkspaceMissing(WorkspaceStreamEvent event) async {
    if (_missingWorkspaceDialogOpen || _activeWorkspace == null) return;
    _missingWorkspaceDialogOpen = true;
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Workspace no longer exists'),
          content: const Text('The active workspace was removed from disk.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('dismiss'),
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('locate'),
              child: const Text('Locate'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('close'),
              child: const Text('Close Workspace'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'close' || action == 'locate') {
        await _unloadActiveWorkspace();
        if (action == 'locate') {
          await _handleOpenWorkspace();
        }
      }
    } finally {
      _missingWorkspaceDialogOpen = false;
    }
  }

  Future<void> _unloadActiveProject() async {
    final projectPath = _selectedProject?.path;
    setState(() {
      _selectedProject = null;
      _showEditorPage = false;
      _testTree = null;
      if (projectPath != null) {
        _editor.tabs = _editorTabs
            .where(
              (tab) => !tab.path
                  .replaceAll('\\', '/')
                  .startsWith(projectPath.replaceAll('\\', '/')),
            )
            .toList();
        _editor.activePath = _editor.tabs.isEmpty
            ? null
            : _editor.tabs.first.path;
      } else {
        _editor.tabs = [];
        _editor.activePath = null;
      }
    });
    await _editor.loadFileTree();
    await _refreshGit();
    await _loadIndexStatus();
  }

  Future<void> _unloadActiveWorkspace() async {
    setState(() {
      _workspace.activeWorkspace = null;
      _selectedProject = null;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSearchPage = false;
      _showEditorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _editor.reset();
      _gitStatus = null;
      _gitHistory = [];
      _testTree = null;
      _indexStatus = null;
      _searchResults = [];
      _liveNotification = null;
    });
    await _loadRecent();
  }

  void _onContentChanged(String path, String content) =>
      _editor.onContentChanged(path, content);

  void _scheduleLanguageRefresh() => _editor.scheduleLanguageRefresh();

  Future<void> _refreshLanguageFeatures() => _editor.refreshLanguageFeatures();

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
        _editor.setStatusMessage('Formatted document');
      });
      _scheduleLanguageRefresh();
    } catch (error) {
      await _showError('Format Document', error);
    }
  }

  Future<void> _editorFormatSelection() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final start = tab.cursorLine;
    final end = tab.cursorLine;
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
        _editor.setStatusMessage('Formatted selection');
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
    final token = EditorShellController.extractRobotTokenAt(
          tab.content,
          _cursorLine,
          _cursorColumn,
        ) ??
        _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
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
      await _openDefinitionResult(definition, token);
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
              decoration: const InputDecoration(
                hintText: 'Filter symbols in file',
              ),
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
                    .where(
                      (item) =>
                          query.isEmpty ||
                          item.name.toLowerCase().contains(query),
                    )
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
          title: const Text('Find Symbol in Project'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: queryController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search symbols in this project',
              ),
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
    setState(() => _revealProblemsToken++);
    unawaited(
      _openFile(
        diagnostic.filePath,
        line: diagnostic.line,
        column: diagnostic.column,
      ),
    );
  }

  void _revealProblemsPanel() {
    setState(() => _revealProblemsToken++);
  }

  void _showSidebarPanel(SidebarPanel panel) {
    setState(() {
      _activePanel = panel;
      _sidePanelCollapsed = false;
      if (panel == SidebarPanel.tests) {
        _showExecutionPage = true;
      } else if (panel == SidebarPanel.search) {
        _showSearchPage = true;
      } else if (panel == SidebarPanel.sourceControl) {
        _showSourceControl = true;
        unawaited(_refreshGit());
      } else if (panel == SidebarPanel.reports) {
        _showReportsPage = true;
        _showDoctorPage = false;
        unawaited(_loadReports());
      } else if (panel == SidebarPanel.doctor) {
        _showDoctorPage = true;
        _showReportsPage = false;
      } else if (panel == SidebarPanel.explorer) {
        _showExecutionPage = false;
        _showSearchPage = false;
        _showSourceControl = false;
        _showReportsPage = false;
        _showDoctorPage = false;
        _showPackageManager = false;
        _showPluginManager = false;
        _showEnvironmentManager = false;
      }
    });
  }

  void _menuFind({bool replace = false}) {
    _editorPageKey.currentState?.showFind(replace: replace);
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
      final result = await _gateway.writeFile(path: path, content: tab.content);
      if (!mounted) return;
      setState(() {
        tab.savedContent = tab.content;
        tab.mtime = result.mtime;
        _editor.setStatusMessage('Saved ${_fileNameFromPath(path)}');
      });
      _appendLog('[info] Saved "$path"');
      await _loadGitStatus();
      unawaited(_refreshLanguageFeatures());
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
    final tab = _activeEditorTab;
    final cursorToken = tab == null
        ? null
        : (EditorShellController.extractRobotTokenAt(
              tab.content,
              _cursorLine,
              _cursorColumn,
            ) ??
            _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn));
    final token = cursorToken ?? _editorTokenName();
    if (token == null) {
      setState(() {
        _editor.setStatusMessage(
          'Place the cursor on a symbol or select one in the outline.',
        );
      });
      return;
    }

    setState(() {
      _editor.setStatusMessage(null);
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final definition = await _gateway.languageDefinition(
        name: token,
        filePath: tab?.path,
        line: tab == null ? null : _cursorLine,
        column: tab == null ? null : _cursorColumn,
        content: tab?.content,
      );
      if (!mounted) return;
      await _openDefinitionResult(definition, token);
    } catch (error) {
      _appendLog('[warn] Definition lookup failed: $error');
      await _showError('Go to Definition', error);
    }
  }

  Future<void> _openDefinitionResult(
    IndexedSymbolInfo? definition,
    String token,
  ) async {
    if (definition == null) {
      setState(() {
        _editor.setStatusMessage('No definition found for "$token".');
      });
      return;
    }
    final candidates = definition.definitions.isNotEmpty
        ? definition.definitions
        : <IndexedSymbolInfo>[definition];
    IndexedSymbolInfo? chosen = candidates.first;
    if (candidates.length > 1) {
      chosen = await showDialog<IndexedSymbolInfo>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('Go to Definition — $token'),
          children: [
            for (final item in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(item),
                child: Text(
                  '${item.name}  ·  ${item.filePath}:${item.line}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      );
      if (chosen == null) return;
    }
    await _openFile(chosen.filePath, line: chosen.line);
  }

  Future<void> _editorFindReferences() async {
    final token = _editorTokenName();
    if (token == null) {
      setState(() {
        _editor.setStatusMessage(
          'Place the cursor on a symbol or select one in the outline.',
        );
      });
      return;
    }

    setState(() {
      _editor.setStatusMessage(null);
      _editorReferences = [];
      _editorHover = null;
    });

    try {
      final refs = await _gateway.languageReferences(name: token);
      if (!mounted) return;
      setState(() {
        _editorReferences = refs;
        if (refs.isEmpty) {
          _editor.setStatusMessage('No references found for "$token".');
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
        _editor.setStatusMessage(
          'Place the cursor on a symbol or select one in the outline.',
        );
      });
      return;
    }

    setState(() {
      _editor.setStatusMessage(null);
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final hover = await _gateway.languageHover(name: token);
      if (!mounted) return;
      setState(() {
        _editorHover = hover;
        if (hover == null) {
          _editor.setStatusMessage('No hover info for "$token".');
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
    await _revealPathInOs(path);
  }

  Future<void> _revealPathInOs(String path) async {
    try {
      await ExplorerFileActions.revealInOs(path);
      if (!mounted) return;
      setState(() {
        _editor.setStatusMessage(
          '${ExplorerFileActions.revealLabel()}: ${ExplorerFileActions.basename(path)}',
        );
      });
    } catch (error) {
      await _showError(ExplorerFileActions.revealLabel(), error);
    }
  }

  Future<void> _copyAbsolutePath(List<String> paths) async {
    if (paths.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: paths.join('\n')));
    if (!mounted) return;
    setState(() {
      _editor.setStatusMessage(
        paths.length == 1
            ? 'Copied absolute path'
            : 'Copied ${paths.length} absolute paths',
      );
    });
  }

  Future<void> _copyRelativePath(List<String> paths) async {
    if (paths.isEmpty) return;
    final root = (_selectedProject?.path ?? _activeWorkspace?.path ?? '')
        .replaceAll('\\', '/');
    final relatives = <String>[];
    for (final path in paths) {
      final normalized = path.replaceAll('\\', '/');
      var relative = normalized;
      if (root.isNotEmpty &&
          (normalized == root || normalized.startsWith('$root/'))) {
        relative = normalized == root
            ? '.'
            : normalized.substring(root.length + 1);
      }
      relatives.add(relative);
    }
    await Clipboard.setData(ClipboardData(text: relatives.join('\n')));
    if (!mounted) return;
    setState(() {
      _editor.setStatusMessage(
        paths.length == 1
            ? 'Copied relative path'
            : 'Copied ${paths.length} relative paths',
      );
    });
  }

  Future<void> _explorerCreateEntry({
    required String parentPath,
    required String name,
    required bool isDirectory,
  }) async {
    final path = ExplorerFileActions.joinPath(parentPath, name);
    try {
      if (isDirectory) {
        await _gateway.createDirectory(path: path);
        await _editor.ensureExpanded(parentPath);
        await _editor.refreshParentOf(path);
      } else {
        final created = await _gateway.createFile(
          path: path,
          content: ExplorerFileActions.initialContentFor(name),
        );
        await _editor.ensureExpanded(parentPath);
        await _editor.refreshParentOf(created.path);
        await _openFile(created.path);
      }
    } catch (error) {
      await _showError(isDirectory ? 'New Folder' : 'New File', error);
    }
  }

  Future<void> _explorerRenameEntry({
    required String path,
    required String newName,
  }) async {
    try {
      final result = await _gateway.renamePath(path: path, newName: newName);
      // Tabs/tree update via workspace live events; nudge parent refresh.
      await _editor.refreshParentOf(result.oldPath ?? path);
      await _editor.refreshParentOf(result.path);
    } catch (error) {
      await _showError('Rename', error);
    }
  }

  Future<void> _explorerDeleteEntry(List<String> paths) async {
    final targets = ExplorerFileActions.pruneNestedPaths(paths);
    if (targets.isEmpty) return;
    final title = targets.length == 1
        ? 'Delete ${ExplorerFileActions.basename(targets.first)}?'
        : 'Delete ${targets.length} items?';
    final content = targets.length == 1
        ? 'This action cannot be undone.'
        : 'These ${targets.length} items will be permanently deleted.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('explorer-delete-dialog'),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('explorer-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    Object? firstError;
    var deleted = 0;
    for (final path in targets) {
      try {
        await _gateway.deletePath(path: path);
        await _closeTabsUnder(path);
        _editor.removePathFromTree(path);
        await _editor.refreshParentOf(path);
        deleted += 1;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (!mounted) return;
    if (deleted > 0) {
      setState(() {
        _editor.setStatusMessage(
          deleted == 1 ? 'Deleted 1 item' : 'Deleted $deleted items',
        );
      });
    }
    if (firstError != null) {
      await _showError('Delete', firstError);
    }
  }

  Future<void> _closeTabsUnder(String path) async {
    final normalized = path.replaceAll('\\', '/');
    final victims = _editorTabs
        .where((tab) {
          final tabPath = tab.path.replaceAll('\\', '/');
          return tabPath == normalized || tabPath.startsWith('$normalized/');
        })
        .map((tab) => tab.path)
        .toList();
    for (final tabPath in victims) {
      await _closeTabWithoutDirtyPrompt(tabPath);
    }
  }

  Future<void> _closeTabWithoutDirtyPrompt(String path) async {
    final tabIndex = _editorTabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    final updated = [..._editorTabs]..removeAt(tabIndex);
    String? nextPath;
    setState(() {
      _pushRecentlyClosed(path);
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
      _editor.workspaceProblems = [
        for (final item in _editor.workspaceProblems)
          if (item.filePath != path) item,
      ];
      _editorHover = null;
      _editorReferences = [];
    });
    if (nextPath != null) {
      await _loadOutline(nextPath!);
    }
  }

  Future<void> _explorerDuplicateEntry(String path) async {
    try {
      final result = await _gateway.duplicatePath(path: path);
      await _editor.refreshParentOf(result.path);
      if (!result.isDir) {
        await _openFile(result.path);
      }
    } catch (error) {
      await _showError('Duplicate', error);
    }
  }

  Future<void> _explorerMoveEntry({
    required List<String> sourcePaths,
    required String destinationParentPath,
  }) async {
    final sources = ExplorerFileActions.pruneNestedPaths(sourcePaths);
    if (sources.isEmpty) return;

    Object? firstError;
    var moved = 0;
    for (final sourcePath in sources) {
      try {
        final result = await _gateway.movePath(
          path: sourcePath,
          destinationDir: destinationParentPath,
        );
        _editor.removePathFromTree(sourcePath);
        final root = (_selectedProject?.path ?? _activeWorkspace?.path ?? '')
            .replaceAll('\\', '/');
        final destNorm = destinationParentPath.replaceAll('\\', '/');
        final destIsRoot = root.isNotEmpty && destNorm == root;
        if (!destIsRoot) {
          await _editor.ensureExpanded(destinationParentPath);
        }
        await _editor.refreshParentOf(sourcePath);
        await _editor.refreshParentOf(result.path);
        // Keep open tabs pointing at the new path.
        final normalized = sourcePath.replaceAll('\\', '/');
        final movedTabs = <int>[];
        for (var i = 0; i < _editorTabs.length; i++) {
          final tabPath = _editorTabs[i].path.replaceAll('\\', '/');
          if (tabPath == normalized || tabPath.startsWith('$normalized/')) {
            movedTabs.add(i);
          }
        }
        if (movedTabs.isNotEmpty) {
          setState(() {
            final next = [..._editorTabs];
            for (final i in movedTabs) {
              final tab = next[i];
              final oldPath = tab.path;
              final tabPath = oldPath.replaceAll('\\', '/');
              final suffix = tabPath == normalized
                  ? ''
                  : tabPath.substring(normalized.length);
              final newPath = '${result.path.replaceAll('\\', '/')}$suffix';
              next[i] = EditorTabInfo(
                path: newPath,
                content: tab.content,
                savedContent: tab.savedContent,
                mtime: tab.mtime,
                cursorLine: tab.cursorLine,
                cursorColumn: tab.cursorColumn,
              );
              if (_editor.activePath == oldPath) {
                _editor.activePath = newPath;
              }
            }
            _editor.tabs = next;
          });
        }
        moved += 1;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (!mounted) return;
    if (moved > 1) {
      setState(() {
        _editor.setStatusMessage('Moved $moved items');
      });
    }
    if (firstError != null) {
      await _showError('Move', firstError);
    }
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
    if (!await _ensureWorkspace(
      message: 'Open a project before searching symbols.',
    )) {
      return;
    }
    setState(() {
      _activePanel = SidebarPanel.search;
      _showSearchPage = true;
      _showEditorPage = false;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showExecutionPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _execution.selectedReport = null;
      _searchKind = kind;
      _searchResults = [];
      _selectedSymbol = null;
    });
    _loadIndexStatus();
    unawaited(_runSearch());
  }

  Future<void> _openCommandPalette() async {
    if (!mounted) return;
    final commands = _paletteCommands();
    await showCommandPalette(
      context: context,
      commands: commands,
      searchWorkspace: _activeWorkspace == null
          ? null
          : _paletteWorkspaceSearch,
    );
  }

  List<PaletteItem> _paletteCommands() {
    final hasWorkspace = _activeWorkspace != null;
    final hasProject = _selectedProject != null;
    final hasEnv = _activeEnvironment != null && _activeEnvironment!.available;
    final hasEditor = _activeEditorPath != null;

    return [
      PaletteItem(
        id: 'project.new',
        title: 'New Project',
        subtitle: 'Create a Robot Framework project',
        icon: Icons.note_add_outlined,
        kind: PaletteItemKind.command,
        keywords: const ['create'],
        onSelect: () => unawaited(_handleNewStandaloneProject()),
      ),
      PaletteItem(
        id: 'project.open',
        title: 'Open Project',
        subtitle: 'Open any Robot Framework project folder',
        icon: Icons.folder_special_outlined,
        kind: PaletteItemKind.command,
        onSelect: () => unawaited(_handleOpenProject()),
      ),
      PaletteItem(
        id: 'workspace.open',
        title: 'Open Workspace',
        subtitle: 'Advanced: open a multi-project workspace',
        icon: Icons.folder_open_outlined,
        kind: PaletteItemKind.command,
        onSelect: () => unawaited(_handleOpenWorkspace()),
      ),
      PaletteItem(
        id: 'workspace.new',
        title: 'New Workspace',
        subtitle: 'Advanced: create a multi-project workspace',
        icon: Icons.add,
        kind: PaletteItemKind.command,
        keywords: const ['create'],
        onSelect: () => unawaited(_handleNewWorkspace()),
      ),
      if (hasWorkspace) ...[
        PaletteItem(
          id: 'project.new.in_workspace',
          title: 'New Project in Workspace',
          icon: Icons.note_add_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleNewProject()),
        ),
        PaletteItem(
          id: 'project.import',
          title: 'Import Project',
          icon: Icons.file_download_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleImportProject()),
        ),
        PaletteItem(
          id: 'env.manage',
          title: 'Manage Environments',
          icon: Icons.memory_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleManageEnvironments()),
        ),
        PaletteItem(
          id: 'packages.open',
          title: 'Open Package Manager',
          icon: Icons.inventory_2_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleOpenPackageManager()),
        ),
        PaletteItem(
          id: 'plugins.open',
          title: 'Open Plugin Manager',
          icon: Icons.extension_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleOpenPluginManager()),
        ),
        PaletteItem(
          id: 'git.open',
          title: 'Open Source Control',
          icon: Icons.source_outlined,
          kind: PaletteItemKind.command,
          keywords: const ['git'],
          onSelect: () => unawaited(_handleOpenSourceControl()),
        ),
        PaletteItem(
          id: 'reports.open',
          title: 'Open Reports',
          icon: Icons.bar_chart_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_openReports()),
        ),
        PaletteItem(
          id: 'doctor.open',
          title: 'Open Robot Doctor',
          subtitle: ShellShortcutActivators.label('⇧⌘D', 'Ctrl+Shift+D'),
          icon: Icons.health_and_safety_outlined,
          kind: PaletteItemKind.command,
          keywords: const ['health', 'findings', 'inspect'],
          onSelect: () => unawaited(_openDoctor()),
        ),
        PaletteItem(
          id: 'search.symbols',
          title: 'Search Symbols',
          subtitle: 'Open the full search page',
          icon: Icons.search,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_openSearchPanel()),
        ),
        PaletteItem(
          id: 'index.rebuild',
          title: 'Rebuild Index',
          icon: Icons.refresh,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_rebuildIndex()),
        ),
      ],
      if (hasProject && hasEnv) ...[
        PaletteItem(
          id: 'run.file',
          title: 'Run Current File',
          subtitle: 'F5',
          icon: Icons.play_arrow_rounded,
          kind: PaletteItemKind.command,
          keywords: const ['execute', 'test', 'f5'],
          onSelect: () => unawaited(_handleRunFile()),
        ),
        PaletteItem(
          id: 'run.project',
          title: 'Run Project',
          icon: Icons.playlist_play_rounded,
          kind: PaletteItemKind.command,
          keywords: const ['execute', 'test'],
          onSelect: () => unawaited(_handleRunProject()),
        ),
      ],
      if (_executionStatus.isActive)
        PaletteItem(
          id: 'run.stop',
          title: 'Stop Execution',
          subtitle: 'Shift+F5',
          icon: Icons.stop_rounded,
          kind: PaletteItemKind.command,
          keywords: const ['cancel', 'halt'],
          onSelect: () => unawaited(_handleStopExecution()),
        ),
      if (hasEditor) ...[
        PaletteItem(
          id: 'file.save',
          title: 'Save File',
          subtitle: ShellShortcutActivators.label('⌘S', 'Ctrl+S'),
          icon: Icons.save_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_saveActive()),
        ),
        PaletteItem(
          id: 'file.saveAll',
          title: 'Save All',
          subtitle: ShellShortcutActivators.label('⌘⇧S', 'Ctrl+Shift+S'),
          icon: Icons.save_as_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_saveAll()),
        ),
        PaletteItem(
          id: 'file.closeTab',
          title: 'Close Editor Tab',
          subtitle: ShellShortcutActivators.label('⌘W', 'Ctrl+W'),
          icon: Icons.close,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_closeActiveTab()),
        ),
        PaletteItem(
          id: 'editor.format',
          title: 'Format Document',
          subtitle: ShellShortcutActivators.label('⇧⌥F', 'Shift+Alt+F'),
          icon: Icons.format_align_left,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorFormatDocument()),
        ),
        PaletteItem(
          id: 'editor.formatSelection',
          title: 'Format Selection',
          icon: Icons.format_indent_increase,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorFormatSelection()),
        ),
        PaletteItem(
          id: 'editor.find',
          title: 'Find',
          subtitle: ShellShortcutActivators.label('⌘F', 'Ctrl+F'),
          icon: Icons.search,
          kind: PaletteItemKind.command,
          onSelect: () => _menuFind(),
        ),
        PaletteItem(
          id: 'editor.replace',
          title: 'Replace',
          subtitle: ShellShortcutActivators.label('⌘H', 'Ctrl+H'),
          icon: Icons.find_replace,
          kind: PaletteItemKind.command,
          onSelect: () => _menuFind(replace: true),
        ),
        PaletteItem(
          id: 'editor.wordWrap',
          title: _wordWrap ? 'Disable Word Wrap' : 'Enable Word Wrap',
          icon: Icons.wrap_text,
          kind: PaletteItemKind.command,
          onSelect: () => setState(() => _editor.wordWrap = !_editor.wordWrap),
        ),
        PaletteItem(
          id: 'editor.definition',
          title: 'Go to Definition',
          subtitle: 'F12',
          icon: Icons.subdirectory_arrow_right,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorGoToDefinition()),
        ),
        PaletteItem(
          id: 'editor.peek',
          title: 'Peek Definition',
          icon: Icons.visibility_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorPeekDefinition()),
        ),
        PaletteItem(
          id: 'editor.references',
          title: 'Find References',
          icon: Icons.link,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorFindReferences()),
        ),
        PaletteItem(
          id: 'editor.hover',
          title: 'Show Hover Info',
          icon: Icons.info_outline,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorHoverLookup()),
        ),
        PaletteItem(
          id: 'editor.problems',
          title: 'Show Problems',
          subtitle: ShellShortcutActivators.label('⌘⇧M', 'Ctrl+Shift+M'),
          icon: Icons.error_outline,
          kind: PaletteItemKind.command,
          keywords: const ['diagnostics'],
          onSelect: _revealProblemsPanel,
        ),
        PaletteItem(
          id: 'view.terminal',
          title: 'Toggle Terminal',
          subtitle: ShellShortcutActivators.label('⌘`', 'Ctrl+`'),
          icon: Icons.terminal,
          kind: PaletteItemKind.command,
          keywords: const ['shell', 'console'],
          onSelect: _toggleTerminal,
        ),
        PaletteItem(
          id: 'view.sidebar',
          title: 'Toggle Side Bar',
          subtitle: ShellShortcutActivators.label('⌘B', 'Ctrl+B'),
          icon: Icons.view_sidebar_outlined,
          kind: PaletteItemKind.command,
          onSelect: _toggleSidebar,
        ),
        PaletteItem(
          id: 'view.search',
          title: 'Search in Project',
          subtitle: ShellShortcutActivators.label('⌘⇧F', 'Ctrl+Shift+F'),
          icon: Icons.search,
          kind: PaletteItemKind.command,
          onSelect: _openProjectSearch,
        ),
        PaletteItem(
          id: 'view.tests',
          title: 'Show Tests',
          icon: Icons.play_circle_outline,
          kind: PaletteItemKind.command,
          keywords: const ['execution', 'run', 'logs'],
          onSelect: () => unawaited(_revealTests()),
        ),
        if (_recentlyClosedPaths.isNotEmpty)
          PaletteItem(
            id: 'file.reopenClosed',
            title: 'Reopen Closed Editor',
            subtitle: ShellShortcutActivators.label('⌘⇧T', 'Ctrl+Shift+T'),
            icon: Icons.restore,
            kind: PaletteItemKind.command,
            onSelect: () => unawaited(_reopenClosedTab()),
          ),
      ],
      for (final path in _recentFiles.take(8))
        PaletteItem(
          id: 'recent:$path',
          title: _fileNameFromPath(path),
          subtitle: path,
          icon: Icons.history,
          kind: PaletteItemKind.file,
          onSelect: () => unawaited(_openFile(path)),
        ),
    ];
  }

  Future<List<PaletteItem>> _paletteWorkspaceSearch(String query) async {
    final items = <PaletteItem>[];
    final needle = query.toLowerCase();

    for (final path in _flattenCachedFilePaths()) {
      final name = _fileNameFromPath(path).toLowerCase();
      if (!name.contains(needle) && !path.toLowerCase().contains(needle)) {
        continue;
      }
      // Skip noisy venv internals in palette results.
      if (path.contains(
            '${Platform.pathSeparator}site-packages${Platform.pathSeparator}',
          ) ||
          path.contains('/site-packages/') ||
          path.contains('\\site-packages\\')) {
        continue;
      }
      items.add(
        PaletteItem(
          id: 'file:$path',
          title: _fileNameFromPath(path),
          subtitle: path,
          icon: Icons.description_outlined,
          kind: PaletteItemKind.file,
          onSelect: () => unawaited(_openFile(path)),
        ),
      );
      if (items.length >= 20) break;
    }

    try {
      final symbols = await _gateway.workspaceSymbols(query: query, limit: 20);
      for (final symbol in symbols) {
        items.add(
          PaletteItem(
            id: 'symbol:${symbol.id}',
            title: symbol.name,
            subtitle: '${symbol.kind.label} · ${symbol.filePath}',
            icon: Icons.code,
            kind: PaletteItemKind.symbol,
            onSelect: () =>
                unawaited(_openFile(symbol.filePath, line: symbol.line)),
          ),
        );
      }
    } catch (_) {
      // Symbol search is best-effort in the palette.
    }

    return items.take(40).toList();
  }

  List<String> _flattenCachedFilePaths() {
    final paths = <String>[];
    void walk(List<FileTreeNode> list) {
      for (final node in list) {
        if (node.isDir) {
          walk(_editor.childrenOf(node));
        } else {
          paths.add(node.path);
        }
      }
    }

    walk(_editor.fileTree);
    return paths;
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
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      return;
    }

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
      if (definition == null) {
        setState(() {
          _navigationMessage = 'No definition found for "${symbol.name}".';
        });
        return;
      }
      await _openDefinitionResult(definition, symbol.name);
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
    if (_showSearchPage || _activePanel == SidebarPanel.search) {
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
    if (_showDoctorPage || _activePanel == SidebarPanel.doctor) {
      return _CenterView.doctor;
    }
    if (_selectedEnvironment != null) return _CenterView.environment;
    if (_selectedProject != null) return _CenterView.project;
    return _CenterView.placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _workspace.backendStatus == 'connected';
    final activeEnvironment = _activeEnvironment;

    return RobotStudioMenuBar(
      actions: AppMenuBarActions(
        hasActiveFile: _activeEditorPath != null,
        hasOpenTabs: _editorTabs.isNotEmpty,
        hasWorkspace: _activeWorkspace != null,
        wordWrap: _wordWrap,
        canStop: _executionStatus.isActive,
        onNewProject: () => unawaited(_handleNewStandaloneProject()),
        onOpenProject: () => unawaited(_handleOpenProject()),
        onOpenWorkspace: () => unawaited(_handleOpenWorkspace()),
        onSave: () => unawaited(_saveActive()),
        onSaveAll: () => unawaited(_saveAll()),
        onCloseEditor: () => unawaited(_closeActiveTab()),
        onReopenClosedEditor: () => unawaited(_reopenClosedTab()),
        onRevealInFolder: () => unawaited(_revealCurrentFile()),
        onFind: () => _menuFind(),
        onReplace: () => _menuFind(replace: true),
        onFindInProject: _openProjectSearch,
        onFormatDocument: () => unawaited(_editorFormatDocument()),
        onFormatSelection: () => unawaited(_editorFormatSelection()),
        onToggleWordWrap: () =>
            setState(() => _editor.wordWrap = !_editor.wordWrap),
        onCommandPalette: () => unawaited(_openCommandPalette()),
        onQuickOpen: () => unawaited(_openCommandPalette()),
        onToggleSidebar: _toggleSidebar,
        onToggleTerminal: _toggleTerminal,
        onShowProblems: _revealProblemsPanel,
        onShowExplorer: () => _showSidebarPanel(SidebarPanel.explorer),
        onShowSearch: () => _showSidebarPanel(SidebarPanel.search),
        onShowSourceControl: () => unawaited(_handleOpenSourceControl()),
        onShowTests: () => unawaited(_revealTests()),
        onShowReports: () => unawaited(_openReports()),
        onShowDoctor: () => unawaited(_openDoctor()),
        onGoToDefinition: () => unawaited(_editorGoToDefinition()),
        onPeekDefinition: () => unawaited(_editorPeekDefinition()),
        onFindReferences: () => unawaited(_editorFindReferences()),
        onGoToSymbolInFile: () => unawaited(_editorOpenSymbol()),
        onFindSymbolInProject: () => unawaited(_editorWorkspaceSymbol()),
        onShowHover: () => unawaited(_editorHoverLookup()),
        onRunFile: () => unawaited(_handleRunFile()),
        onRunProject: () => unawaited(_handleRunProject()),
        onStop: () => unawaited(_handleStopExecution()),
      ),
      child: Shortcuts(
        shortcuts: ShellShortcutActivators.flutterShortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
              onInvoke: (_) {
                unawaited(_openCommandPalette());
                return null;
              },
            ),
            QuickOpenIntent: CallbackAction<QuickOpenIntent>(
              onInvoke: (_) {
                unawaited(_openCommandPalette());
                return null;
              },
            ),
            SaveFileIntent: CallbackAction<SaveFileIntent>(
              onInvoke: (_) {
                unawaited(_saveActive());
                return null;
              },
            ),
            SaveAllFilesIntent: CallbackAction<SaveAllFilesIntent>(
              onInvoke: (_) {
                unawaited(_saveAll());
                return null;
              },
            ),
            CloseActiveTabIntent: CallbackAction<CloseActiveTabIntent>(
              onInvoke: (_) {
                unawaited(_closeActiveTab());
                return null;
              },
            ),
            ReopenClosedTabIntent: CallbackAction<ReopenClosedTabIntent>(
              onInvoke: (_) {
                unawaited(_reopenClosedTab());
                return null;
              },
            ),
            NextEditorTabIntent: CallbackAction<NextEditorTabIntent>(
              onInvoke: (_) {
                _cycleEditorTab(forward: true);
                return null;
              },
            ),
            PreviousEditorTabIntent: CallbackAction<PreviousEditorTabIntent>(
              onInvoke: (_) {
                _cycleEditorTab(forward: false);
                return null;
              },
            ),
            ToggleSidebarIntent: CallbackAction<ToggleSidebarIntent>(
              onInvoke: (_) {
                _toggleSidebar();
                return null;
              },
            ),
            ToggleTerminalIntent: CallbackAction<ToggleTerminalIntent>(
              onInvoke: (_) {
                _toggleTerminal();
                return null;
              },
            ),
            FindInProjectIntent: CallbackAction<FindInProjectIntent>(
              onInvoke: (_) {
                _openProjectSearch();
                return null;
              },
            ),
            FormatDocumentIntent: CallbackAction<FormatDocumentIntent>(
              onInvoke: (_) {
                unawaited(_editorFormatDocument());
                return null;
              },
            ),
            ShowProblemsIntent: CallbackAction<ShowProblemsIntent>(
              onInvoke: (_) {
                _revealProblemsPanel();
                return null;
              },
            ),
            RunFileIntent: CallbackAction<RunFileIntent>(
              onInvoke: (_) {
                unawaited(_handleRunFile());
                return null;
              },
            ),
            StopExecutionIntent: CallbackAction<StopExecutionIntent>(
              onInvoke: (_) {
                unawaited(_handleStopExecution());
                return null;
              },
            ),
            ShowDoctorIntent: CallbackAction<ShowDoctorIntent>(
              onInvoke: (_) {
                unawaited(_openDoctor());
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Stack(
                children: [
                  Column(
                    children: [
                      AppToolbar(
                        projectLabel: _chromeContextLabel,
                        environmentLabel:
                            activeEnvironment?.name ?? 'No environment',
                        environmentNames: _environments
                            .map((item) => item.name)
                            .toList(),
                        selectedEnvironmentName: activeEnvironment?.name,
                        environmentBroken:
                            activeEnvironment?.available == false,
                        onEnvironmentSelected: _handleActivateByName,
                        onManageEnvironments: _handleManageEnvironments,
                        backendConnected: connected,
                        onRun: _handleRunFile,
                        onRunProject: _handleRunProject,
                        onStop: _handleStopExecution,
                        isExecutionRunning: _executionStatus.isActive,
                        executionStatusLabel: _executionStatus.label,
                        executionElapsedLabel: _elapsedLabel,
                        onExecutionStatusTap: _revealTests,
                        canRun:
                            _selectedProject != null &&
                            (activeEnvironment == null ||
                                activeEnvironment.available),
                        canRunProject:
                            _selectedProject != null &&
                            (activeEnvironment == null ||
                                activeEnvironment.available),
                        onOpenWorkspace: _handleOpenWorkspace,
                        onOpenProject: _handleOpenProject,
                        onNewWorkspace: _handleNewWorkspace,
                        onOpenSearch: () => unawaited(_openCommandPalette()),
                        gitBranchLabel: _gitStatus?.repository.branch,
                        gitBranches: _gitBranchNames,
                        onGitBranchSelected: _handleGitCheckout,
                        onGitCreateBranch: _handleGitCreateBranch,
                        onGitDeleteBranch: _handleGitDeleteBranch,
                        onGitFetch: () =>
                            _handleGitRemote('fetch', _gateway.fetchGit),
                        onGitPull: () =>
                            _handleGitRemote('pull', _gateway.pullGit),
                        onGitPush: () =>
                            _handleGitRemote('push', _gateway.pushGit),
                        showGitRemoteActions:
                            _gitStatus?.repository.isRepository == true,
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
                                  if (SidePanel.hasSideContent(panel)) {
                                    _sidePanelCollapsed = false;
                                  }
                                  if (panel == SidebarPanel.tests) {
                                    _showExecutionPage = true;
                                    _showEditorPage = false;
                                  } else {
                                    _showExecutionPage = false;
                                  }
                                  if (panel == SidebarPanel.search) {
                                    _showSearchPage = true;
                                    _showEditorPage = false;
                                    _showEnvironmentManager = false;
                                    _showPackageManager = false;
                                    _showPluginManager = false;
                                    _showSourceControl = false;
                                    _showReportsPage = false;
                                    _showDoctorPage = false;
                                    _selectedEnvironment = null;
                                    _selectedPackage = null;
                                    _execution.selectedReport = null;
                                  } else {
                                    _showSearchPage = false;
                                    if (panel == SidebarPanel.explorer) {
                                      _showEnvironmentManager = false;
                                      _showPackageManager = false;
                                      _showPluginManager = false;
                                      _showSourceControl = false;
                                      _showReportsPage = false;
                                      _showDoctorPage = false;
                                      _selectedPackage = null;
                                      _execution.selectedReport = null;
                                      if (_editorTabs.isNotEmpty &&
                                          _activeEditorPath != null) {
                                        _showEditorPage = true;
                                      }
                                    } else if (panel == SidebarPanel.packages ||
                                        panel == SidebarPanel.plugins ||
                                        panel == SidebarPanel.reports ||
                                        panel == SidebarPanel.doctor ||
                                        panel == SidebarPanel.sourceControl) {
                                      _showEditorPage = false;
                                    }
                                  }
                                });
                                if (panel == SidebarPanel.packages) {
                                  _handleOpenPackageManager();
                                } else if (panel == SidebarPanel.plugins) {
                                  _handleOpenPluginManager();
                                } else if (panel ==
                                    SidebarPanel.sourceControl) {
                                  _handleOpenSourceControl();
                                } else if (panel == SidebarPanel.reports) {
                                  _openReports();
                                } else if (panel == SidebarPanel.doctor) {
                                  _openDoctor();
                                } else if (panel == SidebarPanel.tests) {
                                  _loadExecutionHistory();
                                  _loadTestSuites();
                                } else if (panel == SidebarPanel.search) {
                                  _loadIndexStatus();
                                  unawaited(_runSearch());
                                }
                              },
                            ),
                            if (!_sidePanelCollapsed)
                              SidePanel(
                                panel: _activePanel,
                                width: _sidePanelWidth,
                                workspace: _activeWorkspace,
                                projects: _projects,
                                isLoadingProjects: _loadingProjects,
                                selectedProject: _selectedProject,
                                onSelectProject: _handleSelectProject,
                                onNewProject: _handleNewStandaloneProject,
                                onImportProject: _handleImportProject,
                                recentRuns: _reportRuns.take(8).toList(),
                                onSelectReport: _selectReport,
                                testSuites: _testSuites,
                                onSelectTestSuite: (suite) {
                                  unawaited(
                                    _openFile(suite.filePath, line: suite.line),
                                  );
                                },
                                testTree: _testTree,
                                isLoadingTestTree: _loadingTestTree,
                                testFilter: _testFilter,
                                onTestFilterChanged: _handleTestFilterChanged,
                                onRefreshTests: () =>
                                    unawaited(_loadTestTree()),
                                onRunAllTests: () =>
                                    unawaited(_handleRunAllTests()),
                                onRunCurrentFileTests: () =>
                                    unawaited(_handleRunCurrentFileTests()),
                                onRunFailedTests: () =>
                                    unawaited(_handleRunFailedTests()),
                                onRunTestNode: (node) =>
                                    unawaited(_handleRunTestNode(node)),
                                onOpenTestNode: _handleOpenTestNode,
                                onRevealTestNode: _handleRevealTestNode,
                                onExpandTestNode: _expandTestNode,
                                currentEditorPath: _activeEditorPath,
                                onOpenProject: _handleOpenProject,
                                onRunProject: _selectedProject == null
                                    ? null
                                    : _handleRunProject,
                                fileRows: _editor.visibleFileRows(),
                                isLoadingFileTree: _editor.loadingFileTree,
                                onOpenFile: _openFile,
                                onToggleDirectory: (path) =>
                                    unawaited(_editor.toggleDirectory(path)),
                                gitFileStatuses: _gitFileStatuses,
                                fileTreeKey: _fileTreeKey,
                                onEnsureExpanded: (path) =>
                                    _editor.ensureExpanded(path),
                                onCreateEntry: _explorerCreateEntry,
                                onRenameEntry: _explorerRenameEntry,
                                onDeleteEntry: _explorerDeleteEntry,
                                onDuplicateEntry: _explorerDuplicateEntry,
                                onMoveEntry: _explorerMoveEntry,
                                onCopyRelativePath: (paths) =>
                                    unawaited(_copyRelativePath(paths)),
                                onCopyAbsolutePath: (paths) =>
                                    unawaited(_copyAbsolutePath(paths)),
                                onRevealInOs: (path) =>
                                    unawaited(_revealPathInOs(path)),
                                onCollapseAllFolders: () {
                                  _editor.collapseAllFolders();
                                },
                                outline: _documentOutline,
                                isLoadingOutline: _loadingOutline,
                                selectedOutlineId: _selectedOutlineSymbol?.id,
                                onOutlineSelect: (symbol) {
                                  setState(() {
                                    _editor.selectedOutlineSymbol = symbol;
                                    _editor.jumpToLine = symbol.line;
                                    _showEditorPage = true;
                                  });
                                },
                              ),
                            if (SidePanel.hasSideContent(_activePanel) &&
                                !_sidePanelCollapsed)
                              SidePanelResizeHandle(
                                onDragDelta: (dx) {
                                  setState(() {
                                    _sidePanelWidth = (_sidePanelWidth + dx)
                                        .clamp(
                                          SidePanel.minWidth,
                                          SidePanel.maxWidth,
                                        );
                                  });
                                },
                              ),
                            Expanded(child: _buildCenter()),
                          ],
                        ),
                      ),
                      BottomPanel(
                        logLines: _logLines,
                        problems: _workspaceProblems,
                        isLoadingProblems: false,
                        problemCount: _workspaceProblems.length,
                        workingDirectory:
                            _activeWorkspace?.path ?? _selectedProject?.path,
                        toggleTerminalToken: _toggleTerminalToken,
                        revealProblemsToken: _revealProblemsToken,
                        onProblemSelected: _handleProblemSelected,
                      ),
                      StatusBar(
                        projectName:
                            _selectedProject?.name ?? _activeWorkspace?.name,
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
                            .where(
                              (item) =>
                                  item.severity == DiagnosticSeverity.error,
                            )
                            .length,
                        warningCount: _workspaceProblems
                            .where(
                              (item) =>
                                  item.severity == DiagnosticSeverity.warning,
                            )
                            .length,
                        onProblemsTap: _workspaceProblems.isEmpty
                            ? null
                            : _revealProblemsPanel,
                        robotVersion: _activeEnvironment?.robotVersion,
                        pythonVersion: _activeEnvironment?.pythonVersion,
                        notification: _liveNotification,
                        backendUnavailable: !connected,
                      ),
                    ],
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black38,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  if (_progressOverlay != null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 36,
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _progressOverlay!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_envPromptMessage != null && _envPromptActions != null)
                    EnvironmentPromptToast(
                      title: _envPromptTitle ?? 'Python environment required',
                      message: _envPromptMessage!,
                      actions: _envPromptActions!,
                      onDismiss: _dismissEnvironmentPrompt,
                    ),
                ],
              ),
            ),
          ),
        ),
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
        onOpenProject: _handleOpenProject,
        onOpenRecentWorkspace: _handleOpenRecentWorkspace,
        onOpenRecentProject: _handleOpenRecentProject,
        onNewProject: _handleNewStandaloneProject,
        onImportProject: null,
        onManageEnvironments: _activeWorkspace == null
            ? null
            : _handleManageEnvironments,
        activeEnvironmentLabel: _activeEnvironment?.name,
        backendUnavailable: _workspace.backendStatus != 'connected',
        recentRuns: _executionHistory.take(3).toList(),
        runningStatus: _executionStatus.isActive ? _executionStatus : null,
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
        onContinueWorking: _workspace.activeWorkspace == null
            ? null
            : _handleContinueWorking,
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
        isLoading: _loadingReports,
        dashboard: _reportsDashboard,
        isLoadingDashboard: _loadingDashboard,
        selected: _selectedReport,
        onRefresh: _loadReports,
        onOpenXml: _openReportXml,
        onOpenLog: _openReportLog,
        onOpenReport: _openReportHtml,
        onReveal: _revealReport,
        onDelete: _deleteSelectedReport,
        onRunSuite: _selectedProject == null ? null : _handleRunProject,
      ),
      _CenterView.doctor => DoctorPage(
        gateway: _gateway,
        onJumpToSource: (path, {line, column}) {
          unawaited(_openFile(path, line: line, column: column));
        },
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
        key: _editorPageKey,
        tabs: _editorTabs,
        activePath: _activeEditorPath,
        wordWrap: _wordWrap,
        hover: _editorHover,
        references: _editorReferences,
        statusMessage: _editorStatusMessage,
        onDismissStatusMessage: () =>
            setState(() => _editor.setStatusMessage(null)),
        breadcrumb: _buildBreadcrumb(),
        completionItems: _completionItems,
        diagnostics: _editorDiagnostics,
        hoverTooltip: _hoverTooltip,
        peekDefinition: _peekDefinition,
        jumpToLine: _jumpToLine,
        jumpToColumn: _jumpToColumn,
        onSelectTab: _selectTab,
        onCloseTab: _closeTab,
        onTabContextAction: _handleTabContextAction,
        onContentChanged: _onContentChanged,
        onSave: _saveActive,
        onHoverRequest: (line, column) =>
            unawaited(_editor.requestHoverTooltip(line: line, column: column)),
        onHoverExit: _editor.clearHoverTooltip,
        onCtrlClick: _editorCtrlClickDefinition,
        onClosePeek: () => setState(() => _editor.peekDefinition = null),
        onCursorChanged: _editor.onCursorChanged,
      ),
      _CenterView.placeholder => _WorkspaceOpenPlaceholder(
        workspace: _activeWorkspace!,
        projects: _projects,
        onNewProject: _handleNewStandaloneProject,
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
    required this.onNewProject,
    required this.onImportProject,
    required this.onManageEnvironments,
  });

  final WorkspaceInfo workspace;
  final List<ProjectInfo> projects;
  final VoidCallback onNewProject;
  final VoidCallback onImportProject;
  final VoidCallback onManageEnvironments;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
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
                    : 'Open a project from the Explorer, or create a new one.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onNewProject,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New Project'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onImportProject,
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Import Project'),
                  ),
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
      ),
    );
  }
}
