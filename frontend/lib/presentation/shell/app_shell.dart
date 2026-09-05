import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend_host.dart';
import '../../core/gateway/models/workspace_event_info.dart';
import '../../core/gateway/rest_transport_gateway.dart';
import '../../core/gateway/transport_gateway.dart';
import '../../core/language/robot_library_edit.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/studio_file_picker.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../preferences/preferences_leave_binding.dart';
import '../preferences/preferences_page.dart';
import '../widgets/unsaved_changes_dialog.dart';
import '../environment/clone_environment_dialog.dart';
import '../environment/create_environment_dialog.dart';
import '../environment/delete_environment_dialog.dart';
import '../environment/environment_details_panel.dart';
import '../environment/environment_manager_page.dart';
import '../environment/import_environment_dialog.dart';
import '../environment/python_install_guidance.dart';
import '../editor/editor_page.dart';
import '../editor/editor_run_gutter.dart';
import '../editor/editor_tabs_bar.dart';
import '../execution/execution_page.dart';
import '../execution/run_target.dart';
import '../execution/stop_execution_dialog.dart';
import '../git/add_remote_dialog.dart';
import '../git/git_identity_dialog.dart';
import '../git/source_control_page.dart';
import '../packages/package_details_panel.dart';
import '../packages/package_manager_page.dart';
import '../packages/already_installed_package_dialog.dart';
import '../packages/package_progress_dialog.dart';
import '../packages/search_packages_dialog.dart';
import '../packages/uninstall_package_dialog.dart';
import '../panels/bottom_panel.dart';
import '../libraries/library_explorer_controller.dart';
import '../panels/side_panel.dart';
import '../plugins/plugin_details_panel.dart';
import '../plugins/plugin_manager_page.dart';
import '../project/import_project_dialog.dart';
import '../project/new_project_dialog.dart';
import '../project/project_details_panel.dart';
import '../doctor/doctor_page.dart';
import '../reports/delete_run_dialog.dart';
import '../reports/reports_page.dart';
import '../run_configuration/manage_run_configurations_dialog.dart';
import '../run_configuration/run_configuration_edit_dialog.dart';
import '../insights/insights_page.dart';
import '../search/command_palette.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/sidebar_panel.dart';
import '../toolbar/app_toolbar.dart';
import 'app_menu_bar.dart';
import 'large_run_guard.dart';
import 'shell_shortcuts.dart';
import '../widgets/side_panel_resize_handle.dart';
import '../widgets/environment_prompt_toast.dart';
import '../widgets/app_toast.dart';
import '../widgets/timed_loading_indicator.dart';
import '../widgets/error_dialog.dart';
import '../widgets/guidance_dialog.dart';
import '../widgets/virtual_file_tree.dart';
import '../workspace/explorer_file_actions.dart';
import '../workspace/new_workspace_dialog.dart';
import '../workspace/welcome_screen.dart';
import 'controllers/editor_shell_controller.dart';
import 'controllers/execution_shell_controller.dart';
import 'controllers/git_shell_controller.dart';
import 'controllers/workspace_live_controller.dart';
import 'controllers/workspace_shell_controller.dart';
import 'shell_paths.dart';
import 'status_bar.dart';

enum _CenterView {
  welcome,
  settings,
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
  insights,
  editor,
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    TransportGateway? gateway,
    TransportGateway? apiClient,
    this.themePreference,
    this.accentPreference,
  }) : _gateway = gateway ?? apiClient;

  /// Supports both [gateway] and legacy [apiClient] parameter names.
  final TransportGateway? _gateway;

  /// Publishes the Appearance preference up to [MaterialApp], which owns the
  /// theme. The shell cannot theme itself — a `Theme` it returns sits below its
  /// own `State.context`.
  final ValueNotifier<String>? themePreference;

  /// Publishes the accent colour id (`teal`, `blue`, …) for [MaterialApp]
  /// light/dark palettes.
  final ValueNotifier<String>? accentPreference;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  SidebarPanel _activePanel = SidebarPanel.explorer;

  late final TransportGateway _gateway;
  late final AppSettingsController _settings;
  late final WorkspaceShellController _workspace;
  late final ExecutionShellController _execution;
  late final EditorShellController _editor;
  late final GitShellController _git;
  late final WorkspaceLiveController _live;
  Timer? _autoSaveTimer;
  String? _liveNotification;

  /// Ephemeral footer notice (env create success, etc.); preferred over [_liveNotification].
  String? _footerNotice;
  Timer? _footerNoticeTimer;
  String? _progressOverlay;
  bool _missingProjectDialogOpen = false;
  bool _missingWorkspaceDialogOpen = false;
  final GlobalKey<VirtualFileTreeState> _fileTreeKey =
      GlobalKey<VirtualFileTreeState>();
  final GlobalKey<EditorPageState> _editorPageKey =
      GlobalKey<EditorPageState>();
  final GlobalKey<DoctorPageState> _doctorPageKey =
      GlobalKey<DoctorPageState>();
  late final LibraryExplorerController _libraryExplorer;

  void _notify() {
    if (!mounted) return;
    // A modal (Stop execution, errors, …) lives in the navigator overlay.
    // Rebuilding the shell under it — elapsed ticks and console lines fire
    // every few hundred ms during a run — leaves Tooltip / Overlay entries
    // registered on InheritedWidgets they are no longer descendants of
    // (framework.dart notifyClients assertion).
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    setState(() {});
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
  PackageInfo? _selectedPackage;
  List<PackageInfo> _packages = [];
  PackageSort _packageSort = PackageSort.name;
  String _packageQuery = '';
  bool _robotFrameworkInstalled = false;
  bool _loadingPackages = false;
  bool _busy = false;

  bool _startupRestoreAttempted = false;
  String? _envPromptTitle;
  String? _envPromptMessage;
  List<EnvironmentPromptAction>? _envPromptActions;

  ProjectInfo? _selectedProject;
  EnvironmentInfo? _selectedEnvironment;
  List<RunConfigurationInfo> _runConfigurations = [];
  String? _activeRunConfigurationId;
  bool _showExecutionPage = false;
  int _toggleTerminalToken = 0;
  int _revealProblemsToken = 0;
  bool _sidePanelCollapsed = false;
  final List<String> _recentlyClosedPaths = [];
  bool _showReportsPage = false;
  bool _showDoctorPage = false;
  bool _showInsightsPage = false;
  bool _showSettingsPage = false;
  final _preferencesLeave = PreferencesLeaveBinding();
  List<IndexedSymbolInfo> _testSuites = [];
  TestNodeInfo? _testTree;
  bool _loadingTestTree = false;
  String _testFilter = '';
  Timer? _testFilterDebounce;
  IndexStatusInfo? _indexStatus;
  bool _loadingIndexStatus = false;
  InsightsInfo? _insights;
  bool _loadingInsights = false;
  String? _insightsError;
  bool _showEditorPage = false;
  HoverInfo? _editorHover;
  List<SymbolReferenceInfo> _editorReferences = [];

  String get _backendStatus => _workspace.backendStatus;
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

  /// Recents for the toolbar project menu, with the open project first if it
  /// is not already on the list.
  List<ProjectInfo> get _toolbarRecentProjects {
    final selected = _selectedProject;
    final recents = _recentProjects;
    if (selected == null) return recents;
    if (recents.any((item) => item.id == selected.id)) return recents;
    return [selected, ...recents];
  }

  List<String> get _executionLines => _execution.executionLines;
  List<ExecutionInfo> get _executionHistory => _execution.executionHistory;
  ExecutionStatus get _executionStatus => _execution.executionStatus;
  ExecutionInfo? get _currentExecution => _execution.currentExecution;
  List<RunTestFailureInfo> get _failedTests => _execution.failedTests;
  bool get _loadingFailures => _execution.loadingFailures;
  List<RunTestFailureInfo> get _reportFailedTests =>
      _execution.reportFailedTests;
  bool get _loadingReportFailures => _execution.loadingReportFailures;
  bool get _reportFailuresReady => _execution.reportFailuresReady;
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
    WidgetsBinding.instance.addObserver(this);
    _gateway = widget._gateway ?? RestTransportGateway();
    _settings = AppSettingsController(gateway: _gateway);
    _settings.addListener(_onSettingsChanged);
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
    _git = GitShellController(
      gateway: _gateway,
      notify: _notify,
      isMounted: () => mounted,
      appendLog: _appendLog,
      showError: _showError,
      workspace: () => _workspace.activeWorkspace,
      backendConnected: () => _workspace.backendConnected,
    );

    _libraryExplorer = LibraryExplorerController(
      listLibraries: () => _gateway.languageLibraries(),
      getLibrary: (name) => _gateway.languageLibrary(name),
    );
    _live = WorkspaceLiveController(
      notify: _notify,
      isMounted: () => mounted,
      appendLog: _appendLog,
      onFilesystemEvent: _handleLiveFilesystemEvent,
      onGitChanged: _git.refresh,
      onIndexUpdated: _handleLiveIndexUpdated,
      onTestsChanged: () => _loadTestTree(),
      onEnvironmentChanged: _loadEnvironments,
      onProjectMissing: _handleLiveProjectMissing,
      onWorkspaceMissing: _handleLiveWorkspaceMissing,
      onStreamLost: _workspace.markTransportInterrupted,
      onStatusMessage: (message) {
        if (!mounted) return;
        setState(() {
          // Indexing progress lives in the status bar only — no floating toast.
          _liveNotification = message.isEmpty ? null : message;
          final lower = message.toLowerCase();
          if (message.isEmpty ||
              lower.contains('synchronized') ||
              lower.contains('removed') ||
              lower.contains('indexing')) {
            _progressOverlay = null;
          } else if (lower.contains('analyzing')) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_precacheBranding());
    });
    _bootstrap();
  }

  Future<void> _precacheBranding() async {
    if (!mounted) return;
    try {
      await Future.wait([
        precacheImage(
          const AssetImage('assets/branding/logo-mark.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/branding/logo-mark-light.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/branding/logo-wordmark.png'),
          context,
        ),
        precacheImage(
          const AssetImage('assets/branding/logo-wordmark-light.png'),
          context,
        ),
      ]);
    } catch (_) {
      // Still reveal the slots; missing assets should not block chrome.
    }
    if (!mounted) return;
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final wrap = _settings.editor.wordWrap;
    if (_editor.wordWrap != wrap) {
      _editor.wordWrap = wrap;
    }
    widget.themePreference?.value = _settings.appearance.theme.apiValue;
    widget.accentPreference?.value = _settings.appearance.accent.apiValue;
    setState(() {});
  }

  /// Show a transient message in the bottom status bar.
  ///
  /// Pass [ttl] as `null` to keep the notice until the next call (e.g. while
  /// creating an environment in the background).
  void _setFooterNotice(
    String? message, {
    Duration? ttl = const Duration(seconds: 5),
  }) {
    _footerNoticeTimer?.cancel();
    _footerNoticeTimer = null;
    if (!mounted) return;
    setState(() => _footerNotice = message);
    if (message == null || ttl == null) return;
    final expected = message;
    _footerNoticeTimer = Timer(ttl, () {
      if (!mounted) return;
      setState(() {
        if (_footerNotice == expected) {
          _footerNotice = null;
        }
      });
    });
  }

  @override
  void dispose() {
    AppLogger.debug('AppShell dispose', tag: 'Shell');
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _footerNoticeTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _settings.dispose();
    _testFilterDebounce?.cancel();
    _live.dispose();
    _workspace.dispose();
    _execution.dispose();
    _editor.dispose();
    _git.dispose();
    super.dispose();
  }

  void _clearExecutionPageUnlessTests() {
    if (_activePanel != SidebarPanel.tests) {
      _showExecutionPage = false;
    }
  }

  /// Put the editor in the center and drop leftover env/package detail screens
  /// so they cannot sit underneath and reappear when the last tab closes.
  void _enterEditor() {
    _showEditorPage = true;
    _showSettingsPage = false;
    _showExecutionPage = false;
    _clearDetailOverlays();
  }

  void _clearDetailOverlays() {
    _selectedEnvironment = null;
    _selectedPackage = null;
  }

  Future<void> _bootstrap() async {
    AppLogger.debug('Bootstrap start', tag: 'Shell');
    await _settings.load();
    if (!mounted) return;
    await _workspace.startBackendMonitoring(
      onConnected: () async {
        _connectExecutionStream();
        unawaited(_live.connect());
        await _loadRecent();
        await _rehydrateOpenSessionAfterReconnect();
        await _maybeRestoreLastSession();
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

  /// Reopen the project/workspace the UI still shows after a backend restart.
  ///
  /// Backend process memory is empty on restart; health can come back while the
  /// shell still thinks a project is open. Without this, file APIs return
  /// "Open a workspace before accessing files".
  Future<void> _rehydrateOpenSessionAfterReconnect() async {
    if (!mounted || _backendStatus != 'connected') return;
    final project = _workspace.selectedProject;
    final workspace = _workspace.activeWorkspace;
    if (project == null && workspace == null) return;
    if (_busy) return;

    setState(() => _busy = true);
    try {
      if (project != null) {
        AppLogger.info(
          'Rehydrating open project after backend reconnect',
          tag: 'Shell',
          data: project.path,
        );
        final result = await _gateway.openProjectByPath(project.path);
        if (!mounted) return;
        await _applyOpenedWorkspace(
          result.workspace,
          successMessage: 'Reconnected — project "${project.name}"',
          selectedProject: result.project,
          detectedEnvironments: result.detectedEnvironments,
        );
        return;
      }

      AppLogger.info(
        'Rehydrating open workspace after backend reconnect',
        tag: 'Shell',
        data: workspace!.path,
      );
      final opened = await _gateway.openWorkspace(workspace.path);
      if (!mounted) return;
      await _applyOpenedWorkspace(
        opened,
        successMessage: 'Reconnected — workspace "${workspace.name}"',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[warn] Could not rehydrate session after reconnect: $error');
      AppLogger.warn(
        'Session rehydrate failed after backend reconnect',
        tag: 'Shell',
        error: error,
      );
    }
  }

  /// Reopen the most recent project (or workspace) once after cold start.
  ///
  /// Soft-fails to the welcome screen when the path is gone or open fails —
  /// no modal, just a log line. Editor tabs are intentionally not restored.
  Future<void> _maybeRestoreLastSession() async {
    if (_startupRestoreAttempted) return;
    _startupRestoreAttempted = true;
    if (!mounted || _workspace.activeWorkspace != null) return;
    if (!_settings.appearance.restoreLastProject) return;

    final project = _recentProjects.isNotEmpty ? _recentProjects.first : null;
    final workspace = _recentWorkspaces.isNotEmpty
        ? _recentWorkspaces.first
        : null;
    if (project == null && workspace == null) return;

    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (project != null) {
        AppLogger.info(
          'Restoring last project',
          tag: 'Shell',
          data: project.path,
        );
        final result = await _gateway.openProjectByPath(project.path);
        if (!mounted) return;
        await _applyOpenedWorkspace(
          result.workspace,
          successMessage: 'Restored project "${project.name}"',
          selectedProject: result.project,
          detectedEnvironments: result.detectedEnvironments,
        );
        return;
      }

      AppLogger.info(
        'Restoring last workspace',
        tag: 'Shell',
        data: workspace!.path,
      );
      final opened = await _gateway.openWorkspace(workspace.path);
      if (!mounted) return;
      await _applyOpenedWorkspace(
        opened,
        successMessage: 'Restored workspace "${workspace.name}"',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final label = project != null
          ? 'project "${project.name}"'
          : 'workspace "${workspace!.name}"';
      _appendLog('[warn] Could not restore last $label: $error');
      AppLogger.info(
        'Startup restore failed — staying on welcome',
        tag: 'Shell',
        data: '$error',
      );
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
        _runConfigurations = [];
        _activeRunConfigurationId = null;
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
      // Open-project used to race the env toast ahead of this list; dismiss if
      // a project already has environments (e.g. restored "default").
      if (environments.isNotEmpty) {
        _dismissEnvironmentPrompt();
      }
      await _loadPackages();
      await _loadRunConfigurations();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workspace.loadingEnvironments = false;
        _appendLog('[warn] Could not load environments: $error');
      });
      // Don't await — a hung run-config request must not delay the env toast.
      unawaited(_loadRunConfigurations());
    }
  }

  Future<void> _loadRunConfigurations() async {
    if (_selectedProject == null || _backendStatus != 'connected') {
      if (!mounted) return;
      setState(() {
        _runConfigurations = [];
        _activeRunConfigurationId = null;
      });
      return;
    }
    try {
      final bundle = await _gateway.listRunConfigurations();
      if (!mounted) return;
      setState(() {
        _runConfigurations = bundle.configurations;
        _activeRunConfigurationId = bundle.activeId;
      });
    } catch (error) {
      if (!mounted) return;
      _appendLog('[warn] Could not load run configurations: $error');
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
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showPluginManager = true;
      _showInsightsPage = false;
      _showSourceControl = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.plugins;
      _clearExecutionPageUnlessTests();
    });
    await _loadPlugins();
  }

  Future<void> _handleOpenSourceControl() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before using source control.',
    )) {
      return;
    }
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showSourceControl = true;
      _showInsightsPage = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.sourceControl;
      _clearExecutionPageUnlessTests();
    });
    await _git.refresh();
  }

  Future<void> _handleGitCommit({List<String>? files}) async {
    if (_git.commitController.text.trim().isEmpty) {
      await _showError('Commit', 'Commit message is required.');
      return;
    }
    if (!_git.isRepository) {
      await _showError('Commit', 'Not a Git repository.');
      return;
    }
    if (!await _ensureGitIdentity()) return;
    await _git.commit(files: files);
  }

  Future<bool> _ensureGitIdentity() async {
    final current = _git.status?.repository.identity;
    if (current != null && current.isComplete) return true;
    return _saveGitIdentity(
      identity: current,
      toastMessage: 'Git identity saved',
    );
  }

  Future<void> _handleEditGitIdentity() async {
    await _saveGitIdentity(
      identity: _git.status?.repository.identity,
      toastMessage: 'Git identity updated',
    );
  }

  Future<bool> _saveGitIdentity({
    required GitIdentityInfo? identity,
    required String toastMessage,
  }) async {
    if (!mounted) return false;
    final result = await showGitIdentityDialog(context, identity: identity);
    if (result == null || !mounted) return false;
    final saved = await _git.applyIdentity(
      name: result.name,
      email: result.email,
      scope: result.scope,
    );
    if (!saved || !mounted) return saved;
    showAppToast(context, message: toastMessage, icon: Icons.badge_outlined);
    return true;
  }

  Future<void> _handleAddGitRemote() async {
    if (!mounted) return;
    final existing = _git.status?.repository.remotes ?? const [];
    final current = existing.isEmpty
        ? null
        : existing.firstWhere(
            (remote) => remote.name == 'origin',
            orElse: () => existing.first,
          );
    final result = await showAddGitRemoteDialog(
      context,
      initialName: current?.name ?? 'origin',
      initialUrl: current?.url ?? '',
    );
    if (result == null || !mounted) return;
    final added = await _git.addRemote(name: result.name, url: result.url);
    if (!added || !mounted) return;
    showAppToast(
      context,
      message: 'Remote ${result.name} ready — you can Push',
      icon: Icons.cloud_done_outlined,
    );
  }

  Future<void> _handleEnablePlugin(PluginInfo plugin) async {
    try {
      final updated = await _gateway.enablePlugin(plugin.id);
      if (!mounted) return;
      setState(() => _selectedPlugin = updated);
      await _loadPlugins();
    } catch (error) {
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
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
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showReportsPage = true;
      _showDoctorPage = false;
      _showInsightsPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.reports;
      _clearExecutionPageUnlessTests();
      _selectLatestReportFromCache();
    });
    await _hydrateSelectedReport();
  }

  void _selectLatestReportFromCache() {
    _execution.selectedReport ??= _reportRuns.isNotEmpty
        ? _reportRuns.first
        : (_executionHistory.isNotEmpty ? _executionHistory.first : null);
  }

  Future<void> _hydrateSelectedReport() async {
    final cached = _selectedReport;
    if (cached != null) {
      unawaited(_loadReportFailedTests(cached));
      unawaited(_refreshReportDetails(cached));
    }
    await _loadReports();
    if (!mounted) return;
    final selected = _selectedReport;
    if (selected == null || selected.id == cached?.id) return;
    unawaited(_loadReportFailedTests(selected));
    unawaited(_refreshReportDetails(selected));
  }

  Future<void> _openDoctor() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before running Robot Doctor.',
    )) {
      return;
    }
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showDoctorPage = true;
      _showReportsPage = false;
      _showInsightsPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _execution.selectedReport = null;
      _activePanel = SidebarPanel.doctor;
      _clearExecutionPageUnlessTests();
    });
  }

  Future<void> _openInsightsRun(String runId) async {
    for (final run in _reportRuns) {
      if (run.id == runId) {
        await _selectReport(run);
        return;
      }
    }
    try {
      final run = await _gateway.getReport(runId);
      if (!mounted) return;
      await _selectReport(run);
    } catch (error) {
      if (!mounted) return;
      await _showError('Open report', error);
    }
  }

  Future<String?> _loadInsightsLastFailureName(String runId) async {
    try {
      final result = await _gateway.getRunFailures(runId);
      if (result.items.isEmpty) return null;
      return result.items.first.name;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rerunInsightsFile(String path) async {
    if (!path.toLowerCase().endsWith('.robot')) return;
    AppLogger.info(
      'Insights rerun file',
      tag: 'Shell',
      data: {
        'project': _selectedProject?.name,
        'suite': path,
        'env': _activeEnvironment?.name,
      },
    );
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) return;
    await _maybeSaveBeforeRun();
    if (!mounted) return;
    setState(() {
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runFile(
        file: path,
        configurationId: _activeRunConfigurationId,
      );
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

  Future<void> _selectReport(ExecutionInfo run) async {
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _execution.selectedReport = run;
      _showReportsPage = true;
      _showDoctorPage = false;
      _showInsightsPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.reports;
      _clearExecutionPageUnlessTests();
    });
    unawaited(_loadReportFailedTests(run));
    unawaited(_refreshReportDetails(run));
  }

  Future<void> _refreshReportDetails(ExecutionInfo run) async {
    try {
      final fresh = await _gateway.getReport(run.id);
      if (!mounted || _selectedReport?.id != run.id) return;
      setState(() => _execution.selectedReport = fresh);
    } catch (error) {
      _appendLog('[warn] Could not refresh report details: $error');
    }
  }

  Future<void> _loadReportFailedTests(ExecutionInfo run) async {
    if (!run.shouldListFailures) {
      _execution.clearReportFailedTests();
      return;
    }
    await _execution.loadReportFailedTests(run.id);
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
      setState(() {
        _execution.selectedReport = null;
        _execution.reportFailedTests = [];
        _execution.loadingReportFailures = false;
        _execution.reportFailedTestsRunId = null;
        _execution.reportFailuresReady = false;
      });
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
        'suite': _runTargetPath,
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
    final suite = _runTargetPath;
    if (suite == null) {
      if (!mounted) return;
      await showGuidanceDialog(
        context: context,
        title: 'Nothing to run',
        message:
            'Open a .robot suite file in the editor, then press Run. '
            'Selecting a file in Explorer is not enough.',
        primaryLabel: 'OK',
        onPrimary: () {},
        dismissLabel: 'Close',
      );
      return;
    }

    await _maybeSaveBeforeRun();
    if (!mounted) return;

    setState(() {
      _revealExecutionCenter();
    });
    await _connectExecutionStream();

    try {
      final run = await _gateway.runFile(
        file: suite,
        configurationId: _activeRunConfigurationId,
      );
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

    await _maybeSaveBeforeRun();
    if (!mounted) return;

    setState(() {
      _revealExecutionCenter();
    });
    await _connectExecutionStream();

    try {
      final run = await _runWithLargeRunGuard(
        start: ({required bool confirm}) => _gateway.runProject(
          confirm: confirm,
          configurationId: _activeRunConfigurationId,
        ),
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
    if (_execution.executionStatus == ExecutionStatus.stopping) return;
    if (_settings.execution.stopConfirmation) {
      final running = _execution.executionStatus.isActive;
      if (running) {
        final confirmed = await showStopExecutionDialog(
          context,
          suite: _currentExecution?.suite,
          elapsedLabel: _elapsedLabel,
          liveSuite: _execution.liveSuite,
          liveTest: _execution.liveTest,
          liveKeyword: _execution.liveKeyword,
        );
        if (!mounted) return;
        if (!confirmed) {
          setState(() {});
          return;
        }
      }
    }
    _execution.markStopping();
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

  RunConfigurationInfo? get _activeRunConfiguration {
    final id = _activeRunConfigurationId;
    if (id == null) return null;
    for (final item in _runConfigurations) {
      if (item.id == id) return item;
    }
    return null;
  }

  EnvironmentInfo? get _runEnvironment {
    final pinId = _activeRunConfiguration?.environmentId;
    if (pinId != null) {
      for (final env in _environments) {
        if (env.id == pinId) return env;
      }
      return null;
    }
    return _activeEnvironment;
  }

  Future<bool> _ensureRobotReady() async {
    final pinId = _activeRunConfiguration?.environmentId;
    if (pinId != null) {
      final env = _runEnvironment;
      if (env == null || !env.available) {
        if (!mounted) return false;
        await showGuidanceDialog(
          context: context,
          title: 'Configuration environment missing',
          message:
              'This run configuration pins an environment that is no longer '
              'available. Edit the configuration or choose Default.',
          primaryLabel: 'Manage Configurations…',
          onPrimary: () => unawaited(_handleManageRunConfigurations()),
        );
        return false;
      }
      final installed =
          env.robotVersion != null && env.robotVersion!.isNotEmpty;
      if (installed) return true;
      if (!mounted) return false;
      await showGuidanceDialog(
        context: context,
        title: 'Robot Framework required',
        message:
            'Robot Framework is not installed in the configuration '
            'environment "${env.name}". Install it there, or edit the '
            'configuration to use another environment.',
        primaryLabel: 'Manage Configurations…',
        onPrimary: () => unawaited(_handleManageRunConfigurations()),
      );
      return false;
    }
    if (!await _ensureEnvironment(
      message: 'Activate an environment before running tests.',
    )) {
      return false;
    }
    final env = _activeEnvironment;
    final installed =
        _robotFrameworkInstalled ||
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

  bool get _robotFrameworkReady {
    final env = _runEnvironment;
    if (_activeRunConfiguration?.environmentId != null) {
      return env?.robotVersion != null && env!.robotVersion!.isNotEmpty;
    }
    return _robotFrameworkInstalled ||
        (env?.robotVersion != null && env!.robotVersion!.isNotEmpty);
  }

  bool get _canRunTests {
    final env = _runEnvironment;
    final pinId = _activeRunConfiguration?.environmentId;
    if (pinId != null && (env == null || !env.available)) return false;
    final envOk = env == null || env.available;
    return _selectedProject != null && envOk && _robotFrameworkReady;
  }

  /// Prefer the active editor when it is a `.robot` suite.
  String? get _runTargetPath =>
      resolveRunTargetPath(activeEditorPath: _activeEditorPath);

  bool get _canRunFile => _canRunTests && _runTargetPath != null;

  /// Bring the Execution monitor to the front (Run / Tests), keeping tabs mounted.
  Future<void> _revealExecutionCenter() async {
    _execution.prepareNewRun();
    if (!_settings.execution.revealExecutionOnRun) return;
    if (!await _prepareLeaveSettings()) return;
    if (!mounted) return;
    setState(() {
      _showExecutionPage = true;
      _showSettingsPage = false;
      _showEditorPage = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPackageManager = false;
      _showPluginManager = false;
      _showEnvironmentManager = false;
    });
  }

  Future<void> _maybeSaveBeforeRun() async {
    if (!_settings.editor.saveBeforeRun) return;
    final dirty = _editor.tabs.any((tab) => tab.isDirty);
    if (!dirty) return;
    await _saveAll();
  }

  Future<bool> _showLargeRunConfirmDialog({
    required int? count,
    required int threshold,
    String? tag,
  }) async {
    if (!mounted) return false;
    final estimate = (count != null && count > 0) ? '$count' : 'many';
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
  ///
  /// Threshold comes from Settings → Execution → Large Run Threshold
  /// ([AppSettingsController.execution]), matching the backend 409 check.
  Future<ExecutionInfo?> _runWithLargeRunGuard({
    required Future<ExecutionInfo> Function({required bool confirm}) start,
    String? tag,
    bool projectWide = true,
  }) async {
    int? count;
    try {
      count = await _gateway.countTests(tag: tag, projectWide: projectWide);
    } catch (_) {
      count = null;
    }
    final threshold = _settings.execution.largeRunThreshold;
    final needsConfirm = LargeRunGuard.needsConfirmation(
      count: count,
      threshold: threshold,
      tag: tag,
    );
    if (needsConfirm &&
        !await _showLargeRunConfirmDialog(
          count: count,
          threshold: threshold,
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
        threshold: error.threshold ?? threshold,
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
            (text.contains('not installed') || text.contains('not available')));
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
    final selected = await StudioFilePicker.getDirectoryPath(
      dialogTitle: 'Open Workspace',
    );
    if (selected == null) return;
    await _runWorkspaceAction(
      () => _gateway.openWorkspace(selected),
      successMessage: 'Opened workspace',
    );
  }

  Future<void> _handleOpenProject() async {
    final selected = await StudioFilePicker.getDirectoryPath(
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

  /// Spread post-open API work so cold start does not hit the sidecar with a
  /// single parallel burst (REST + WS reconnect was freezing Windows builds).
  void _scheduleProjectOpenLoads({
    List<DetectedEnvironmentInfo> detectedEnvironments = const [],
  }) {
    Future<void> after(Duration delay, Future<void> Function() work) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!mounted || _backendStatus != 'connected') return;
      await work();
    }

    unawaited(
      after(Duration.zero, () async {
        await Future.wait([_editor.loadFileTree(), _loadIndexStatus()]);
      }),
    );

    unawaited(
      after(const Duration(milliseconds: 250), () async {
        try {
          await _loadEnvironments().timeout(const Duration(seconds: 15));
        } catch (_) {
          // Timeout or load error — decide from whatever state we have.
        }
        if (!mounted || _environments.isNotEmpty) return;
        await _showEnvironmentPrompt(detectedEnvironments);
      }),
    );

    unawaited(after(const Duration(milliseconds: 500), _loadExecutionHistory));
    unawaited(after(const Duration(milliseconds: 800), _git.loadStatus));
  }

  Future<void> _applyOpenedWorkspace(
    WorkspaceInfo workspace, {
    required String successMessage,
    ProjectInfo? selectedProject,
    List<DetectedEnvironmentInfo> detectedEnvironments = const [],
  }) async {
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _workspace.activeWorkspace = workspace;
      _selectedProject = selectedProject;
      _selectedEnvironment = null;
      _workspace.environments = [];
      _workspace.loadingEnvironments = false;
      _selectedPackage = null;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSettingsPage = false;
      // Drop previous project's console / failed-tests / run chrome immediately,
      // including when the Tests tab stays open across the switch.
      _execution.resetForWorkspaceChange();
      _insights = null;
      _insightsError = null;
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
      _git.reset();
      _editor.selectedOutlineSymbol = null;
      _busy = false;
    });
    _appendLog(
      selectedProject == null
          ? '[info] $successMessage "${workspace.name}"'
          : '[info] $successMessage',
    );
    // Paint explorer/tests immediately — do not block on recent/projects refetch.
    if (selectedProject != null) {
      setState(() {
        _workspace.projects = [selectedProject];
        _workspace.loadingProjects = true;
      });
    }
    _scheduleProjectOpenLoads(detectedEnvironments: detectedEnvironments);
    unawaited(() async {
      await _loadRecent();
      if (!mounted) return;
      await _loadProjects();
      if (!mounted) return;
      if (selectedProject == null) {
        await _maybeAutoSelectProject();
        return;
      }
      final match = _projects
          .where((item) => item.id == selectedProject.id)
          .toList();
      if (match.isNotEmpty && mounted) {
        setState(() => _selectedProject = match.first);
      }
    }());
  }

  /// Folder to prefill as the parent for a new project: sibling of whatever is
  /// currently open, else the user's home directory.
  ///
  /// Only returns paths that still exist on disk — after an externally deleted
  /// project the in-memory path can briefly linger and must not be offered.
  String? _defaultNewProjectLocation() {
    final current = _selectedProject?.path ?? _activeWorkspace?.path;
    if (current != null && current.isNotEmpty) {
      final parent = ExplorerFileActions.parentPath(current);
      if (Directory(parent).existsSync()) return parent;
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    return Directory(home).existsSync() ? home : null;
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
    if (!mounted) return;
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
    if (_environments.isNotEmpty) {
      _dismissEnvironmentPrompt();
      return;
    }

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
    // on machines with no interpreter installed. Keep a hard timeout so Store
    // alias hangs cannot delay the toast.
    late final bool hasPython;
    try {
      final interpreters = await _gateway.listPythonInterpreters().timeout(
        const Duration(seconds: 4),
      );
      hasPython = interpreters.isNotEmpty;
    } catch (_) {
      // Discovery failed / timed out — still offer create + install, no backend talk.
      if (!mounted || _environments.isNotEmpty) return;
      setState(() {
        _envPromptTitle = 'Python environment required';
        _envPromptMessage =
            'Select an existing environment or create one. If Create fails, '
            'install Python 3 from python.org (Add to PATH) and restart '
            'Robot Studio.';
        _envPromptActions = [
          EnvironmentPromptAction(
            label: 'Create Environment',
            primary: true,
            onPressed: () => unawaited(_createDefaultEnvironmentInBackground()),
          ),
          EnvironmentPromptAction(
            label: 'How to Install',
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
    // Interpreters can take seconds; envs may have loaded while we waited.
    if (!mounted || _environments.isNotEmpty) return;

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
      _setFooterNotice('Using environment "${candidate.name}"');
    } catch (error) {
      _appendLog('[error] $error');
      if (mounted) await _showError('Could not use environment', error);
    }
  }

  Future<void> _createDefaultEnvironmentInBackground() async {
    _appendLog('[info] Creating Python environment in the background…');
    _setFooterNotice('Creating Python environment…', ttl: null);
    try {
      final interpreters = await _gateway.listPythonInterpreters();
      if (interpreters.isEmpty) {
        _setFooterNotice(null);
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
      _setFooterNotice('Environment "default" is ready');
    } catch (error) {
      _appendLog('[error] $error');
      _setFooterNotice(null);
      if (!mounted) return;
      if (PythonInstallGuidance.matchesError(error)) {
        await _showNoPythonInstallGuide();
        return;
      }
      await _showError('Could not create environment', error);
    }
  }

  Future<void> _selectExistingEnvironment() async {
    final selected = await StudioFilePicker.getDirectoryPath(
      dialogTitle: 'Select an existing Python environment',
    );
    if (selected == null) return;
    try {
      await _gateway.importEnvironment(selected);
      await _loadEnvironments();
      _appendLog('[info] Imported environment from $selected');
      _setFooterNotice('Imported environment');
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
    if (!mounted) return;
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
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _activePanel = SidebarPanel.tests;
      _showExecutionPage = true;
      _showSettingsPage = false;
      _showEditorPage = false;
      _sidePanelCollapsed = false;
    });
  }

  void _toggleTerminal() {
    setState(() => _toggleTerminalToken++);
  }

  void _toggleSidebar() {
    setState(() => _sidePanelCollapsed = !_sidePanelCollapsed);
  }

  Future<void> _openUserGuide() async {
    const url = 'https://deekshith-poojary98.github.io/robot-studio/';
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
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

  Future<void> _openProjectSearch() async {
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _activePanel = SidebarPanel.search;
      _sidePanelCollapsed = false;
      _showSettingsPage = false;
      _clearExecutionPageUnlessTests();
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      if (_editorTabs.isNotEmpty && _activeEditorPath != null) {
        _enterEditor();
      }
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
        // Same project-scoped reset as open/create — Tests tab must not keep
        // the previous project's console or failed-tests list.
        _execution.resetForWorkspaceChange();
        _clearExecutionPageUnlessTests();
        _busy = false;
      });
      _appendLog('[info] $successMessage "${project.name}"');
      await _loadProjects();
      await _loadRecent();
      _scheduleProjectOpenLoads();
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
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showEnvironmentManager = true;
      _showPackageManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _clearExecutionPageUnlessTests();
    });
    await _loadEnvironments();
  }

  Future<void> _handleSelectRunConfiguration(String? id) async {
    if (!await _ensureProject(
      message: 'Open a project before choosing a run configuration.',
    )) {
      return;
    }
    try {
      final activeId = await _gateway.activateRunConfiguration(id);
      if (!mounted) return;
      setState(() => _activeRunConfigurationId = activeId);
    } catch (error) {
      if (!mounted) return;
      await _showError('Run configuration', error);
    }
  }

  Future<void> _handleNewRunConfiguration() async {
    if (!await _ensureProject(
      message: 'Open a project before creating a run configuration.',
    )) {
      return;
    }
    if (!mounted) return;
    final draft = await showRunConfigurationEditDialog(
      context,
      environments: _environments,
    );
    if (draft == null || !mounted) return;
    try {
      final created = await _gateway.createRunConfiguration(draft);
      if (!mounted) return;
      setState(() {
        _runConfigurations = [..._runConfigurations, created];
        _activeRunConfigurationId = created.id;
      });
      await _loadRunConfigurations();
    } catch (error) {
      if (!mounted) return;
      await _showError('Create run configuration', error);
    }
  }

  Future<void> _handleManageRunConfigurations() async {
    if (!await _ensureProject(
      message: 'Open a project before managing run configurations.',
    )) {
      return;
    }
    if (!mounted) return;
    await showManageRunConfigurationsDialog(
      context,
      gateway: _gateway,
      environments: _environments,
    );
    if (!mounted) return;
    await _loadRunConfigurations();
  }

  Future<void> _handleOpenPackageManager() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before managing packages.',
    )) {
      return;
    }
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showPackageManager = true;
      _showInsightsPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.packages;
      _clearExecutionPageUnlessTests();
    });
    await _loadPackages();
  }

  Future<void> _handleSelectPackage(PackageInfo package) async {
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _selectedPackage = package;
      _showPackageManager = true;
      _showSettingsPage = false;
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

    var force = false;
    final installed = await _findInstalledPackage(selected.name);
    if (!mounted) return;
    if (installed != null &&
        _samePackageVersion(installed.version, selected.version)) {
      final proceed = await showAlreadyInstalledPackageDialog(
        context,
        name: installed.name,
        version: installed.version,
      );
      if (proceed != true) return;
      force = true;
    }

    await _runPackageOperation(
      title: force ? 'Force Installing Package' : 'Installing Package',
      packageName: '${selected.name} ${selected.version}',
      operation: () => _gateway.installPackage(
        selected.name,
        version: selected.version,
        force: force,
      ),
      successMessage: force ? 'Reinstalled package' : 'Installed package',
    );
  }

  Future<PackageInfo?> _findInstalledPackage(String name) async {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final package in _packages) {
      if (package.name.toLowerCase() == needle) return package;
    }
    try {
      return await _gateway.getPackage(name);
    } catch (_) {
      return null;
    }
  }

  static bool _samePackageVersion(String installed, String selected) {
    return installed.trim().toLowerCase() == selected.trim().toLowerCase();
  }

  Future<void> _handleImportRequirements() async {
    final path = await StudioFilePicker.pickFile(
      dialogTitle: 'Choose a requirements file',
      allowedExtensions: const ['txt', 'in'],
    );
    if (!mounted || path == null) return;
    if (path.trim().isEmpty) {
      await _showError(
        'Import Requirements',
        'The selected file does not have a local path.',
      );
      return;
    }

    final fileName = File(path).uri.pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Text(
          'Install Requirements',
          style: Theme.of(dialogContext).textTheme.titleLarge,
        ),
        content: SizedBox(
          width: AppDialogWidth.form,
          child: Text(
            'Install every package listed in “$fileName” into the active '
            'environment?\n\nExisting packages may be upgraded or downgraded '
            'to match the file.',
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    AppLogger.info('Import requirements selected', tag: 'Shell', data: path);
    await _runPackageOperation(
      title: 'Installing Requirements',
      packageName: fileName,
      operation: () => _gateway.installRequirements(path),
      successMessage: 'Installed requirements from',
    );
  }

  Future<void> _handleExportRequirements() async {
    final projectPath = _selectedProject?.path ?? _activeWorkspace?.path;
    final path = await StudioFilePicker.saveFile(
      dialogTitle: 'Export requirements',
      fileName: 'requirements.txt',
      allowedExtensions: const ['txt', 'in'],
      initialDirectory: projectPath,
    );
    if (!mounted || path == null || path.trim().isEmpty) return;

    var exportPath = path.trim();
    final lower = exportPath.toLowerCase();
    if (!lower.endsWith('.txt') && !lower.endsWith('.in')) {
      exportPath = '$exportPath.txt';
    }

    final fileName = File(exportPath).uri.pathSegments.last;
    AppLogger.info(
      'Export requirements selected',
      tag: 'Shell',
      data: exportPath,
    );
    await _runPackageOperation(
      title: 'Exporting Requirements',
      packageName: fileName,
      operation: () => _gateway.exportRequirements(exportPath),
      successMessage: 'Exported requirements to',
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
      _showEditorPage = false;
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
    if (!mounted) return;
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
    if (!mounted) return;
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
          _showEditorPage = false;
          _clearExecutionPageUnlessTests();
        }
        _busy = false;
      });
      _appendLog('[info] $successMessage "${environment.name}"');
      _setFooterNotice('$successMessage "${environment.name}"');
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
        : _currentExecution;
    final outputDir = latest?.outputDir;
    if (outputDir != null && outputDir.isNotEmpty) {
      unawaited(_editor.refreshParentOf(outputDir));
    }
    if (latest != null) {
      if (latest.resultBadge == 'FAIL' &&
          _settings.execution.autoOpenReportOnFailure) {
        unawaited(_selectReport(latest));
      } else {
        _offerViewReportToast(latest);
      }
      if (latest.shouldListFailures) {
        unawaited(_execution.loadFailedTests(latest.id));
      } else {
        _execution.clearFailedTests();
      }
    }
    await _suggestMissingLibraryInstall();
  }

  static bool _isRunArtifactPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    if (normalized.contains('/.robotstudio/reports/')) return true;
    final name = normalized.split('/').last;
    return name == 'output.xml' ||
        name == 'log.html' ||
        name == 'report.html' ||
        name == 'xunit.xml';
  }

  void _offerViewReportToast(ExecutionInfo run) {
    if (!mounted) return;
    final badge = run.resultBadge;
    final label = () {
      final suite = run.suite.trim();
      if (suite.isNotEmpty) {
        final name = suite.replaceAll('\\', '/').split('/').last;
        return name.isEmpty ? suite : name;
      }
      if (run.projectName.trim().isNotEmpty) return run.projectName.trim();
      return 'Tests';
    }();
    showAppToast(
      context,
      message: switch (badge) {
        'FAIL' => '$label failed',
        'PASS' => '$label passed',
        'NO TESTS' => '$label — no tests ran',
        'ERROR' => '$label did not complete',
        'CANCELLED' => '$label cancelled',
        'ABORTED' => '$label aborted',
        _ => label,
      },
      actionLabel: 'View Report',
      onAction: () => unawaited(_selectReport(run)),
      duration: const Duration(seconds: 6),
      icon: switch (badge) {
        'FAIL' || 'ERROR' => Icons.error_outline,
        'PASS' => Icons.check_circle_outline,
        _ => Icons.info_outline,
      },
      iconColor: switch (badge) {
        'FAIL' || 'ERROR' => context.palette.error,
        'PASS' => context.palette.success,
        'NO TESTS' || 'CANCELLED' || 'ABORTED' => context.palette.warning,
        _ => context.palette.textMuted,
      },
    );
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
      iconColor: context.palette.warning,
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
        iconColor: context.palette.success,
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
      final lazy = q.trim().isEmpty;
      final previous = _testTree;
      var tree = await _gateway.getTestTree(query: q, lazy: lazy);
      var refresh = const <TestNodeInfo>[];
      // Lazy reloads replace hydrated suites with empty shells. Keep children
      // for nodes the user already expanded so the tree does not go blank.
      if (lazy && previous != null) {
        final retained = TestNodeInfo.retainHydratedChildren(previous, tree);
        tree = retained.tree;
        refresh = retained.refresh;
      }
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
      for (final node in refresh) {
        unawaited(_expandTestNode(node));
      }
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

  Future<void> _handleRunSingleTest({
    required String file,
    required String name,
  }) async {
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    await _maybeSaveBeforeRun();
    if (!mounted) return;
    setState(() {
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runTest(
        file: file,
        name: name,
        configurationId: _activeRunConfigurationId,
      );
      if (!mounted) return;
      setState(() {
        _execution.executionStatus = run.status;
        _execution.currentExecution = run;
      });
      _startElapsedTimer();
    } catch (error) {
      if (!mounted) return;
      _appendLog('[error] Test run failed: $error');
      await _handleExecutionError(error);
    }
  }

  Future<void> _handleRunTestAtCursor() async {
    final path = _activeEditorPath;
    if (path == null || !path.toLowerCase().endsWith('.robot')) {
      if (!mounted) return;
      setState(() {
        _editor.setStatusMessage(
          'Open a .robot suite and place the caret in a test case.',
        );
      });
      return;
    }
    final tests = runnableTestsFromOutline(
      _editor.documentAnalysis?.root,
      filePath: path,
    );
    final hit = enclosingRunnableTest(tests, _cursorLine);
    if (hit == null) {
      if (!mounted) return;
      setState(() {
        _editor.setStatusMessage(
          'Place the caret in a test case to run only that test.',
        );
      });
      return;
    }
    await _handleRunSingleTest(file: path, name: hit.name);
  }

  Future<void> _handleRunTestNode(TestNodeInfo node) async {
    if (node.kind == 'test' || node.kind == 'task') {
      if (node.path == null || node.path!.isEmpty) return;
      await _handleRunSingleTest(file: node.path!, name: node.name);
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
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final ExecutionInfo? run;
      if (node.kind == 'suite') {
        run = await _gateway.runTestSuite(
          file: node.path,
          configurationId: _activeRunConfigurationId,
        );
      } else if (node.kind == 'project' || node.kind == 'workspace') {
        run = await _runWithLargeRunGuard(
          start: ({required bool confirm}) => _gateway.runTestSuite(
            confirm: confirm,
            configurationId: _activeRunConfigurationId,
          ),
          projectWide: true,
        );
        if (run == null) return;
      } else {
        return;
      }
      final started = run;
      if (!mounted) return;
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
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _runWithLargeRunGuard(
        start: ({required bool confirm}) => _gateway.runTestSuite(
          confirm: confirm,
          configurationId: _activeRunConfigurationId,
        ),
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
    final path = _runTargetPath;
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
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runTestSuite(
        file: path,
        configurationId: _activeRunConfigurationId,
      );
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
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runFailedTests(
        configurationId: _activeRunConfigurationId,
      );
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

  Future<void> _handleRerunFailedTest(RunTestFailureInfo failure) async {
    if (!failure.canJump) return;
    if (!await _ensureProject(
      message: 'Open a project before running tests.',
    )) {
      return;
    }
    if (!await _ensureRobotReady()) {
      return;
    }
    setState(() {
      _activePanel = SidebarPanel.tests;
      _revealExecutionCenter();
    });
    await _connectExecutionStream();
    try {
      final run = await _gateway.runSelectedTests([
        (file: failure.source, name: failure.name),
      ], configurationId: _activeRunConfigurationId);
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
      if (!await _prepareLeaveSettings()) return;
      setState(() {
        _editor.activePath = path;
        _enterEditor();
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
      if (!await _prepareLeaveSettings()) {
        if (mounted) setState(() => _busy = false);
        return;
      }
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
        _enterEditor();
        _editor.jumpToLine = line;
        _editor.jumpToColumn = column;
        _editorHover = null;
        _editorReferences = [];
        _editor.setStatusMessage(null);
        _busy = false;
      });
      _trackRecentFile(file.path);
      await _loadOutline(file.path);
      _editor.onActiveTabChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _appendLog('[error] Could not open file: $error');
      await _showError('Open file', error);
    }
  }

  Future<bool> _confirmDiscard(String path) async {
    final choice = await showUnsavedChangesDialog(
      context,
      title: 'Unsaved Changes',
      message: 'Save changes to "${_fileNameFromPath(path)}" before closing?',
      discardLabel: "Don't Save",
    );
    switch (choice) {
      case UnsavedChangesChoice.cancel:
        return false;
      case UnsavedChangesChoice.discard:
        return true;
      case UnsavedChangesChoice.save:
        await _saveTab(path);
        final index = _editorTabs.indexWhere((tab) => tab.path == path);
        if (index < 0) return true;
        return !_editorTabs[index].isDirty;
    }
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
          _editor.clearActiveDocument();
          _clearDetailOverlays();
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

    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _editor.activePath = path;
      _enterEditor();
      _editor.restoreCaretFromTab(path);
      _editor.jumpToLine = null;
      _editor.jumpToColumn = null;
      _editorHover = null;
      _editorReferences = [];
      _editor.setStatusMessage(null);
    });
    _editor.onActiveTabChanged();
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
            child: const Text('Keep Mine'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('reload'),
            child: const Text('Reload'),
          ),
        ],
      ),
    );
    if (!mounted) return;
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
            _clearDetailOverlays();
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
    // Dead/missing session — do not refresh trees against a gone root.
    if (_activeWorkspace == null) return;
    final absolute = event.absolutePath ?? event.path;
    if (absolute == null || absolute.isEmpty) return;
    // Report artifacts churn continuously during long runs; ignore so Save
    // and editor stay responsive. Reports refresh when the run finishes.
    if (_isRunArtifactPath(absolute) ||
        (event.oldAbsolutePath != null &&
            _isRunArtifactPath(event.oldAbsolutePath!))) {
      return;
    }

    switch (event.type) {
      case 'FILE_DELETED':
      case 'DIRECTORY_DELETED':
        _doctorPageKey.currentState?.pruneRemovedPaths(
          absolute,
          isDirectory: event.type == 'DIRECTORY_DELETED',
        );
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

  /// Enclosing scopes worth naming in the breadcrumb. Python classes, functions
  /// and methods belong here so a `.py` breadcrumb is not just the file path.
  static const _breadcrumbSymbolKinds = {
    SymbolKind.keyword,
    SymbolKind.testCase,
    SymbolKind.keywordCall,
    SymbolKind.classKind,
    SymbolKind.function,
    SymbolKind.method,
  };

  Future<void> _handleLiveIndexUpdated(WorkspaceStreamEvent event) async {
    await _loadIndexStatus();
    if (_showInsightsPage || _activePanel == SidebarPanel.insights) {
      await _loadInsights();
    }
    final active = _activeEditorPath;
    if (active != null && EditorShellController.isSourcePath(active)) {
      await _loadOutline(active);
      _scheduleLanguageRefresh();
    }
  }

  Future<void> _handleLiveProjectMissing(WorkspaceStreamEvent event) async {
    if (_missingProjectDialogOpen || _selectedProject == null) return;
    _autoSaveTimer?.cancel();
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
    if (_missingWorkspaceDialogOpen) return;
    _missingWorkspaceDialogOpen = true;
    try {
      // Unload immediately — waiting on the dialog left the shell calling
      // files/git APIs against a deleted root, which then crashed New Project.
      if (_activeWorkspace != null) {
        await _unloadActiveWorkspace(force: true);
      }
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Workspace no longer exists'),
          content: const Text(
            'The open project folder was removed from disk. '
            'You can create or open another project from the welcome screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('ok'),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('new'),
              child: const Text('New Project'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'new') {
        await _handleNewStandaloneProject();
      }
    } finally {
      _missingWorkspaceDialogOpen = false;
    }
  }

  Future<void> _unloadActiveProject() async {
    final projectPath = _selectedProject?.path;
    final workspacePath = _activeWorkspace?.path;
    // Standalone projects share the workspace root — Closing must clear the
    // whole session (envs/chip), otherwise "New Project same name" keeps
    // showing `venv · missing` from the deleted life.
    if (projectPath != null &&
        workspacePath != null &&
        sameFsPath(projectPath, workspacePath)) {
      await _unloadActiveWorkspace();
      return;
    }
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
    await _git.refresh();
    await _loadIndexStatus();
  }

  Future<void> _handleCloseProject() async {
    if (_activeWorkspace == null) return;

    final dirtyPaths = _editorTabs
        .where((tab) => tab.isDirty)
        .map((tab) => tab.path)
        .toList();
    for (final path in dirtyPaths) {
      final discard = await _confirmDiscard(path);
      if (!discard) return;
    }

    _autoSaveTimer?.cancel();
    await _execution.disconnectStream();
    await _live.disconnect();
    await _unloadActiveWorkspace();
    if (!mounted) return;
    _appendLog('[info] Closed project — returned to welcome');
  }

  Future<void> _unloadActiveWorkspace({bool force = false}) async {
    if (!force && !await _prepareLeaveSettings()) return;
    setState(() {
      _workspace.activeWorkspace = null;
      _selectedProject = null;
      _selectedEnvironment = null;
      _workspace.environments = [];
      _workspace.loadingEnvironments = false;
      _selectedPackage = null;
      _showEnvironmentManager = false;
      _showPackageManager = false;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _showExecutionPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _editor.reset();
      _execution.resetForWorkspaceChange();
      _git.reset();
      _testTree = null;
      _indexStatus = null;
      _insights = null;
      _insightsError = null;
      _liveNotification = null;
      _runConfigurations = [];
      _activeRunConfigurationId = null;
    });
    await _loadRecent();
  }

  void _onContentChanged(String path, String content) {
    _editor.onContentChanged(path, content);
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (!_settings.editor.autoSave) return;
    if (_missingProjectDialogOpen || _selectedProject == null) return;
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_missingProjectDialogOpen || _selectedProject == null) return;
      unawaited(_saveAll(quiet: true));
    });
  }

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
    String? projectPath;
    String? folderPath;
    if (parts.length >= 2) {
      folder = parts[parts.length - 2];
      folderPath = parts.sublist(0, parts.length - 1).join('/');
    }
    final projectsIndex = parts.indexOf('Projects');
    if (projectsIndex >= 0 && projectsIndex + 1 < parts.length) {
      project = parts[projectsIndex + 1];
      projectPath = parts.sublist(0, projectsIndex + 2).join('/');
    }
    IndexedSymbolInfo? symbol;
    final active = _editor.activeDocumentSymbol;
    if (active != null && _breadcrumbSymbolKinds.contains(active.kind)) {
      symbol = active.toIndexed(tab.path);
    } else {
      for (final item in _documentOutline.reversed) {
        if (item.line <= _cursorLine &&
            _breadcrumbSymbolKinds.contains(item.kind)) {
          symbol = item;
          break;
        }
      }
    }

    final segments = <BreadcrumbSegment>[
      if (_activeWorkspace != null)
        BreadcrumbSegment(
          label: _activeWorkspace!.name,
          path: _activeWorkspace!.path,
        ),
      if (project != null) BreadcrumbSegment(label: project, path: projectPath),
      if (folder != null && folder != project)
        BreadcrumbSegment(label: folder, path: folderPath),
      BreadcrumbSegment(label: fileName, path: tab.path, line: 1),
      if (symbol != null)
        BreadcrumbSegment(
          label: symbol.name,
          path: tab.path,
          line: symbol.line,
        ),
    ];

    return EditorBreadcrumbInfo(
      workspace: _activeWorkspace?.name,
      project: project,
      folder: folder,
      fileName: fileName,
      symbol: symbol,
      segments: segments,
    );
  }

  void _onBreadcrumbTap(BreadcrumbSegment segment) {
    final path = segment.path;
    if (path == null || path.isEmpty) return;
    final lower = path.toLowerCase();
    final isRobotFile = lower.endsWith('.robot') || lower.endsWith('.resource');
    if (isRobotFile || segment.line != null) {
      unawaited(_openFile(path, line: segment.line));
      return;
    }
    unawaited(_editor.ensureExpanded(path));
  }

  Future<void> _editorFormatDocument() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final source = _editorPageKey.currentState?.currentText ?? tab.content;
    try {
      final formatted = await _gateway.languageFormat(
        filePath: tab.path,
        content: source,
      );
      if (!mounted) return;
      final changed = formatted != source;
      setState(() {
        tab.content = formatted;
        _editor.setStatusMessage(
          changed ? 'Formatted document' : 'Already formatted',
        );
      });
      _editorPageKey.currentState?.applyExternalContent(formatted);
      if (changed) _scheduleLanguageRefresh();
    } catch (error) {
      await _showError('Format Document', error);
    }
  }

  Future<void> _editorRenameSymbol() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final isPython = EditorShellController.isPythonPath(tab.path);
    final isRobot = EditorShellController.isRobotPath(tab.path);
    if (!isPython && !isRobot) {
      setState(() {
        _editor.setStatusMessage(
          'Rename Symbol works in Robot and Python files.',
        );
      });
      return;
    }
    final token = _editorCursorToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _editor.setStatusMessage('Place the cursor on a symbol to rename it.');
      });
      return;
    }

    final newName = await _promptForRename(token, isPython: isPython);
    if (newName == null || newName == token) return;

    final source = _editorPageKey.currentState?.currentText ?? tab.content;
    try {
      final result = await _gateway.languageRename(
        filePath: tab.path,
        line: _cursorLine,
        column: _cursorColumn,
        content: source,
        newName: newName,
      );
      if (!mounted) return;
      if (result.error.isNotEmpty) {
        setState(() => _editor.setStatusMessage(result.error));
        return;
      }
      if (result.files.isEmpty) {
        setState(
          () => _editor.setStatusMessage('Nothing to rename for "$token".'),
        );
        return;
      }
      await _applyRenameEdits(result.files, token, newName);
    } catch (error) {
      await _showError('Rename Symbol', error);
    }
  }

  Future<String?> _promptForRename(
    String current, {
    required bool isPython,
  }) async {
    final controller = TextEditingController(text: current);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: current.length,
    );
    final scopeNote = isPython
        ? 'Renames the definition and every usage across the project, '
              'including files that are not open.'
        : 'Renames this user keyword everywhere it is called across the '
              'project, including files that are not open. BuiltIn keywords '
              'cannot be renamed.';
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final palette = context.palette;
        return AlertDialog(
          title: const Text('Rename Symbol'),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          content: SizedBox(
            width: AppDialogWidth.form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Symbol',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  current,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'Menlo',
                    fontFamilyFallback: const [
                      'Consolas',
                      'Courier New',
                      'monospace',
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  scopeNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'New name'),
                  onSubmitted: (value) =>
                      Navigator.of(context).pop(value.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              style: FilledButton.styleFrom(
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// Writes every file the rename touched, keeping open tabs in sync.
  ///
  /// The active buffer is applied through the editor so undo still works; other
  /// files are written to disk because they have no live controller to edit.
  Future<void> _applyRenameEdits(
    List<RenameFileEditInfo> edits,
    String from,
    String to,
  ) async {
    final activePath = _activeEditorTab?.path;
    var written = 0;
    for (final edit in edits) {
      if (edit.filePath == activePath) {
        setState(() => _activeEditorTab!.content = edit.content);
        _editorPageKey.currentState?.applyExternalContent(edit.content);
        written++;
        continue;
      }
      try {
        await _gateway.writeFile(path: edit.filePath, content: edit.content);
        for (final open in _editor.tabs) {
          if (open.path == edit.filePath) {
            setState(() => open.content = edit.content);
          }
        }
        written++;
      } catch (error) {
        _appendLog('[warn] Rename could not write ${edit.filePath}: $error');
      }
    }
    if (!mounted) return;
    final suffix = written == 1 ? 'file' : 'files';
    setState(() {
      _editor.setStatusMessage('Renamed "$from" to "$to" in $written $suffix');
    });
    _scheduleLanguageRefresh();
  }

  Future<void> _editorFormatSelection() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final source = _editorPageKey.currentState?.currentText ?? tab.content;
    final start = tab.cursorLine;
    final end = tab.cursorLine;
    try {
      final formatted = await _gateway.languageFormat(
        filePath: tab.path,
        content: source,
        startLine: start,
        endLine: end,
      );
      if (!mounted) return;
      final changed = formatted != source;
      setState(() {
        tab.content = formatted;
        _editor.setStatusMessage(
          changed ? 'Formatted selection' : 'Already formatted',
        );
      });
      _editorPageKey.currentState?.applyExternalContent(formatted);
      if (changed) _scheduleLanguageRefresh();
    } catch (error) {
      await _showError('Format Selection', error);
    }
  }

  Future<void> _editorPeekDefinition() async {
    final token = _editorCursorToken() ?? _editorTokenName();
    if (token == null) return;
    final tab = _activeEditorTab;
    try {
      // Position matters: a bare name cannot tell an imported `dumps` from a
      // local one, and Jedi needs the caret to resolve either.
      final definition = await _gateway.languageDefinition(
        name: token,
        filePath: tab?.path,
        line: tab == null ? null : _cursorLine,
        column: tab == null ? null : _cursorColumn,
        content: tab?.content,
      );
      if (!mounted) return;
      setState(() => _editor.peekDefinition = definition);
    } catch (error) {
      await _showError('Peek Definition', error);
    }
  }

  Future<void> _editorCtrlClickDefinition() async {
    final tab = _activeEditorTab;
    if (tab == null) return;
    final token = _editorCursorToken();
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

  Future<void> _handleProblemQuickFix(DiagnosticInfo diagnostic) async {
    final fix = diagnostic.quickFix;
    if (fix == null) return;
    if (fix.isInstallPackage) {
      await _runPackageOperation(
        title: 'Installing Package',
        packageName: fix.package!,
        operation: () => _gateway.installPackage(fix.package!),
        successMessage: 'Installed package',
      );
      if (!mounted) return;
      _scheduleLanguageRefresh();
      return;
    }
    if (fix.isInsertLibrary) {
      await _applyInsertLibraryFix(diagnostic.filePath, fix.library!);
    }
  }

  Future<void> _applyInsertLibraryFix(String filePath, String library) async {
    await _openFile(filePath);
    if (!mounted) return;
    EditorTabInfo? tab;
    for (final open in _editor.tabs) {
      if (open.path == filePath) {
        tab = open;
        break;
      }
    }
    if (tab == null) {
      setState(() {
        _editor.setStatusMessage('Open the file to add Library    $library');
      });
      return;
    }
    final target = tab;
    final source = target.path == _activeEditorTab?.path
        ? (_editorPageKey.currentState?.currentText ?? target.content)
        : target.content;
    final updated = insertLibraryImport(source, library);
    if (updated == null) {
      setState(() {
        _editor.setStatusMessage('Library    $library is already imported');
      });
      return;
    }
    if (target.path == _activeEditorTab?.path) {
      setState(() => target.content = updated);
      _editorPageKey.currentState?.applyExternalContent(updated);
    } else {
      setState(() => target.content = updated);
    }
    setState(() {
      _editor.setStatusMessage('Added Library    $library');
    });
    _scheduleLanguageRefresh();
  }

  void _revealProblemsPanel() {
    setState(() => _revealProblemsToken++);
  }

  Future<void> _showSidebarPanel(SidebarPanel panel) async {
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _activePanel = panel;
      _sidePanelCollapsed = false;
      _showSettingsPage = false;
      if (panel == SidebarPanel.tests) {
        _showExecutionPage = true;
      } else if (panel == SidebarPanel.sourceControl) {
        _showSourceControl = true;
        unawaited(_git.refresh());
      } else if (panel == SidebarPanel.reports) {
        _showReportsPage = true;
        _showDoctorPage = false;
        _selectLatestReportFromCache();
        unawaited(_hydrateSelectedReport());
      } else if (panel == SidebarPanel.doctor) {
        _showDoctorPage = true;
        _showReportsPage = false;
      } else if (panel == SidebarPanel.explorer ||
          panel == SidebarPanel.search ||
          panel == SidebarPanel.libraries) {
        _showExecutionPage = false;
        _showSourceControl = false;
        _showReportsPage = false;
        _showDoctorPage = false;
        _showInsightsPage = false;
        _showPackageManager = false;
        _showPluginManager = false;
        _showEnvironmentManager = false;
        if (_editorTabs.isNotEmpty && _activeEditorPath != null) {
          _enterEditor();
        }
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

  Future<void> _saveAll({bool quiet = false}) async {
    for (final tab in _editorTabs) {
      if (tab.isDirty) {
        await _saveTab(tab.path, quiet: quiet);
      }
    }
  }

  Future<void> _saveTab(String path, {bool quiet = false}) async {
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
      });
      _appendLog('[info] Saved "$path"');
      // Don't block Save on git / language refresh — especially mid-run.
      unawaited(_git.loadStatus());
      unawaited(_refreshLanguageFeatures());
    } catch (error) {
      _appendLog('[error] Save failed: $error');
      if (quiet) {
        if (!mounted) return;
        setState(() {
          _editor.setStatusMessage('Auto-save failed — use Save (⌘S)');
        });
        return;
      }
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

    final tab = _activeEditorTab;
    if (tab == null) return null;
    return _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
  }

  /// Token under the caret, using the rules of the file's own language.
  ///
  /// `extractRobotTokenAt` reads indented lines as Robot argument cells split on
  /// two spaces, which is the wrong model for Python — on `    return  x` it
  /// would hand back a cell instead of the identifier being pointed at.
  String? _editorCursorToken() {
    final tab = _activeEditorTab;
    if (tab == null) return null;
    if (EditorShellController.isPythonPath(tab.path)) {
      return _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
    }
    return EditorShellController.extractRobotTokenAt(
          tab.content,
          _cursorLine,
          _cursorColumn,
        ) ??
        _extractWordAtCursor(tab.content, _cursorLine, _cursorColumn);
  }

  Future<void> _editorGoToDefinition() async {
    final tab = _activeEditorTab;
    final token = _editorCursorToken() ?? _editorTokenName();
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
    final IndexedSymbolInfo target;
    if (candidates.length > 1) {
      final picked = await showDialog<IndexedSymbolInfo>(
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
      if (picked == null) return;
      target = picked;
    } else {
      target = candidates.first;
    }
    if (!_isPathInEditableScope(target.filePath)) {
      setState(() {
        _editor.peekDefinition = target;
        _editor.setStatusMessage(
          'Definition is outside this project (${target.filePath}). '
          'Showing peek — stdlib and site-packages are not opened in the editor.',
        );
      });
      return;
    }
    await _openFile(target.filePath, line: target.line);
  }

  /// True when [path] lies under the open workspace or project (editable tree).
  bool _isPathInEditableScope(String path) {
    if (path.trim().isEmpty) return false;
    final normalized = path.replaceAll('\\', '/');
    final roots = <String>[];
    final workspacePath = _activeWorkspace?.path;
    if (workspacePath != null && workspacePath.isNotEmpty) {
      roots.add(workspacePath.replaceAll('\\', '/'));
    }
    final projectPath = _selectedProject?.path;
    if (projectPath != null && projectPath.isNotEmpty) {
      roots.add(projectPath.replaceAll('\\', '/'));
    }
    for (final root in roots) {
      final trimmed = root.endsWith('/')
          ? root.substring(0, root.length - 1)
          : root;
      if (normalized == trimmed) return true;
      if (normalized.startsWith('$trimmed/')) return true;
    }
    return false;
  }

  Future<void> _editorFindReferences() async {
    final token = _editorCursorToken() ?? _editorTokenName();
    if (token == null) {
      setState(() {
        _editor.setStatusMessage(
          'Place the cursor on a symbol or select one in the outline.',
        );
      });
      return;
    }
    final tab = _activeEditorTab;

    setState(() {
      _editor.setStatusMessage(null);
      _editorReferences = [];
      _editorHover = null;
    });

    try {
      final refs = await _gateway.languageReferences(
        name: token,
        filePath: tab?.path,
        line: tab == null ? null : _cursorLine,
        column: tab == null ? null : _cursorColumn,
        content: tab?.content,
      );
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
    final token = _editorCursorToken() ?? _editorTokenName();
    if (token == null) {
      setState(() {
        _editor.setStatusMessage(
          'Place the cursor on a symbol or select one in the outline.',
        );
      });
      return;
    }
    final tab = _activeEditorTab;

    setState(() {
      _editor.setStatusMessage(null);
      _editorHover = null;
      _editorReferences = [];
    });

    try {
      final hover = await _gateway.languageHover(
        name: token,
        filePath: tab?.path,
        line: tab == null ? null : _cursorLine,
        column: tab == null ? null : _cursorColumn,
        content: tab?.content,
      );
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
        final result = await _gateway.deletePath(path: path);
        _doctorPageKey.currentState?.pruneRemovedPaths(
          result.path,
          isDirectory: result.isDir,
        );
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
          _editor.clearActiveDocument();
          _clearDetailOverlays();
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

  Future<void> _handleContinueWorking() async {
    if (_editorTabs.isNotEmpty) {
      final path = _activeEditorPath ?? _editorTabs.first.path;
      if (!await _prepareLeaveSettings()) return;
      setState(() {
        _enterEditor();
      });
      _selectTab(path);
      return;
    }
    if (_recentFiles.isNotEmpty) {
      _openFile(_recentFiles.first);
    }
  }

  Future<void> _openInsights() async {
    if (!await _ensureWorkspace(
      message: 'Open a project before viewing insights.',
    )) {
      return;
    }
    if (!await _prepareLeaveSettings()) return;
    setState(() {
      _showInsightsPage = true;
      _showReportsPage = false;
      _showDoctorPage = false;
      _showSourceControl = false;
      _showPluginManager = false;
      _showPackageManager = false;
      _showEnvironmentManager = false;
      _showSettingsPage = false;
      _showEditorPage = false;
      _selectedEnvironment = null;
      _selectedPackage = null;
      _activePanel = SidebarPanel.insights;
      _clearExecutionPageUnlessTests();
    });
    await _loadInsights();
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

  void _openPreferences() {
    if (!mounted) return;
    setState(() => _showSettingsPage = true);
  }

  Future<void> _closePreferences() async {
    if (!await _prepareLeaveSettings()) return;
    if (!mounted) return;
    setState(() => _showSettingsPage = false);
  }

  /// Prompt when Settings has an unsaved draft. Call before clearing
  /// [_showSettingsPage] on any navigation path.
  Future<bool> _prepareLeaveSettings() async {
    if (!_showSettingsPage) return true;
    return _preferencesLeave.confirmLeave();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final allowed = await _confirmQuitIfNeeded();
    if (allowed) {
      BackendHost.instance?.stopSync();
    }
    return allowed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<bool> _confirmQuitIfNeeded() async {
    if (!mounted) return true;

    final settingsDirty = _showSettingsPage && _preferencesLeave.isDirty;
    final dirtyTabs = _editorTabs.where((tab) => tab.isDirty).toList();
    if (!settingsDirty && dirtyTabs.isEmpty) return true;

    final parts = <String>[];
    if (settingsDirty) {
      parts.add('unsaved Settings changes');
    }
    if (dirtyTabs.length == 1) {
      parts.add('unsaved file "${_fileNameFromPath(dirtyTabs.first.path)}"');
    } else if (dirtyTabs.length > 1) {
      parts.add('${dirtyTabs.length} unsaved files');
    }

    final choice = await showUnsavedChangesDialog(
      context,
      title: 'Unsaved Changes',
      message:
          'You have ${parts.join(' and ')}. Save before quitting, '
          "or discard them?",
      saveLabel: dirtyTabs.length > 1 || settingsDirty ? 'Save All' : 'Save',
    );

    switch (choice) {
      case UnsavedChangesChoice.cancel:
        return false;
      case UnsavedChangesChoice.discard:
        return true;
      case UnsavedChangesChoice.save:
        if (settingsDirty) {
          final saved = await _preferencesLeave.savePending();
          if (!saved) return false;
        }
        if (dirtyTabs.isNotEmpty) {
          await _saveAll();
          if (_editorTabs.any((tab) => tab.isDirty)) return false;
        }
        return true;
    }
  }

  Future<void> _toggleWordWrap() async {
    final next = !_editor.wordWrap;
    setState(() => _editor.wordWrap = next);
    try {
      await _settings.patch({
        'editor': {'word_wrap': next},
      });
    } catch (_) {
      // Local toggle still applied; persistence best-effort.
    }
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
      if (hasWorkspace)
        PaletteItem(
          id: 'project.close',
          title: 'Close Project',
          subtitle: 'Return to the welcome screen',
          icon: Icons.close,
          kind: PaletteItemKind.command,
          keywords: const ['workspace', 'landing', 'welcome', 'exit'],
          onSelect: () => unawaited(_handleCloseProject()),
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
          id: 'run-config.new',
          title: 'New Run Configuration',
          icon: Icons.tune,
          kind: PaletteItemKind.command,
          keywords: const ['run', 'tags', 'variables'],
          onSelect: () => unawaited(_handleNewRunConfiguration()),
        ),
        PaletteItem(
          id: 'run-config.manage',
          title: 'Manage Run Configurations',
          icon: Icons.tune,
          kind: PaletteItemKind.command,
          keywords: const ['run', 'duplicate'],
          onSelect: () => unawaited(_handleManageRunConfigurations()),
        ),
        PaletteItem(
          id: 'packages.open',
          title: 'Open Package Manager',
          icon: Icons.inventory_2_outlined,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_handleOpenPackageManager()),
        ),
        // Beta: Plugin Manager is hidden from the activity bar and palette.
        // Keep _handleOpenPluginManager / PluginManagerPage wired; restore this
        // entry when SidebarPanel.plugins.showInActivityBar is turned back on.
        // PaletteItem(
        //   id: 'plugins.open',
        //   title: 'Open Plugin Manager',
        //   icon: Icons.extension_outlined,
        //   kind: PaletteItemKind.command,
        //   onSelect: () => unawaited(_handleOpenPluginManager()),
        // ),
        PaletteItem(
          id: 'git.open',
          title: 'Open Source Control',
          icon: Icons.call_split_outlined,
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
          id: 'view.insights',
          title: 'Insights',
          subtitle: 'Project composition and run health',
          icon: Icons.insights_outlined,
          kind: PaletteItemKind.command,
          keywords: const ['analytics', 'stats', 'pass rate', 'composition'],
          onSelect: () => unawaited(_openInsights()),
        ),
        PaletteItem(
          id: 'search.symbol',
          title: 'Find Symbol in Project',
          subtitle: ShellShortcutActivators.label('⌘T', 'Ctrl+T'),
          icon: Icons.code,
          kind: PaletteItemKind.command,
          keywords: const ['goto', 'workspace symbol', 'keyword'],
          onSelect: () => unawaited(_editorWorkspaceSymbol()),
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
          id: 'run.testAtCursor',
          title: 'Run Test at Cursor',
          icon: Icons.play_arrow,
          kind: PaletteItemKind.command,
          keywords: const ['execute', 'single', 'one test', 'gutter'],
          onSelect: () => unawaited(_handleRunTestAtCursor()),
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
      if (_executionStatus == ExecutionStatus.running ||
          _executionStatus == ExecutionStatus.starting)
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
          onSelect: () => unawaited(_toggleWordWrap()),
        ),
        PaletteItem(
          id: 'preferences.open',
          title: 'Settings',
          icon: Icons.settings_outlined,
          kind: PaletteItemKind.command,
          onSelect: _openPreferences,
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
          id: 'editor.rename',
          title: 'Rename Symbol',
          subtitle: 'Robot and Python files',
          icon: Icons.drive_file_rename_outline,
          kind: PaletteItemKind.command,
          onSelect: () => unawaited(_editorRenameSymbol()),
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
          title: 'Find in Project',
          subtitle: ShellShortcutActivators.label('⌘⇧F', 'Ctrl+Shift+F'),
          icon: Icons.search,
          kind: PaletteItemKind.command,
          onSelect: _openProjectSearch,
        ),
        PaletteItem(
          id: 'view.libraries',
          title: 'Show Libraries',
          icon: Icons.menu_book_outlined,
          kind: PaletteItemKind.command,
          keywords: const ['keywords', 'libdoc', 'documentation'],
          onSelect: () => _showSidebarPanel(SidebarPanel.libraries),
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
    setState(() {
      _loadingIndexStatus = true;
      _liveNotification = 'Indexing workspace…';
      _progressOverlay = null;
    });
    try {
      final status = await _gateway.rebuildIndex();
      if (!mounted) return;
      setState(() {
        _indexStatus = status;
        _loadingIndexStatus = false;
      });
      // Background job — INDEX_PROGRESS / INDEX_UPDATED drive the rest.
      if (status.state == 'indexing') {
        _appendLog('[info] Symbol index rebuild started');
        return;
      }
      _appendLog('[info] Symbol index rebuilt');
      if (_showInsightsPage || _activePanel == SidebarPanel.insights) {
        await _loadInsights();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingIndexStatus = false;
        _liveNotification = null;
      });
      _appendLog('[error] Index rebuild failed: $error');
      await _showError('Index rebuild', error);
    }
  }

  Future<void> _loadInsights() async {
    if (_workspace.activeWorkspace == null || _backendStatus != 'connected') {
      return;
    }
    setState(() {
      _loadingInsights = true;
      _insightsError = null;
    });
    try {
      final insights = await _gateway.getInsights();
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loadingInsights = false;
        _insightsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInsights = false;
        _insightsError = error.toString();
      });
      _appendLog('[warn] Insights load failed: $error');
    }
  }

  _CenterView get _centerView {
    // Settings outranks the welcome screen so it stays reachable with no
    // project open.
    if (_showSettingsPage) return _CenterView.settings;
    if (_workspace.activeWorkspace == null) return _CenterView.welcome;
    // Run / Tests monitor takes the center while explicitly requested.
    // Jump-to-source clears _showExecutionPage and sets _showEditorPage.
    if (_showExecutionPage) {
      return _CenterView.execution;
    }
    // Empty tabs still count — otherwise env/project details sitting under
    // the editor come back when the last file is closed.
    if (_showEditorPage) {
      return _CenterView.editor;
    }
    if (_activePanel == SidebarPanel.tests) {
      return _CenterView.execution;
    }
    if (_showInsightsPage || _activePanel == SidebarPanel.insights) {
      return _CenterView.insights;
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

    // Theme lives on MaterialApp (see main.dart) so this State's own context —
    // and every dialog route — resolves the active palette.
    return RobotStudioMenuBar(
      actions: AppMenuBarActions(
        hasActiveFile: _activeEditorPath != null,
        hasOpenTabs: _editorTabs.isNotEmpty,
        hasWorkspace: _activeWorkspace != null,
        wordWrap: _wordWrap,
        canStop:
            _executionStatus == ExecutionStatus.running ||
            _executionStatus == ExecutionStatus.starting,
        canRun: _canRunTests,
        onNewProject: () => unawaited(_handleNewStandaloneProject()),
        onOpenProject: () => unawaited(_handleOpenProject()),
        onOpenWorkspace: () => unawaited(_handleOpenWorkspace()),
        onCloseProject: () => unawaited(_handleCloseProject()),
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
        onRenameSymbol: () => unawaited(_editorRenameSymbol()),
        onToggleWordWrap: () => unawaited(_toggleWordWrap()),
        onPreferences: _openPreferences,
        onCommandPalette: () => unawaited(_openCommandPalette()),
        onQuickOpen: () => unawaited(_openCommandPalette()),
        onToggleSidebar: _toggleSidebar,
        onToggleTerminal: _toggleTerminal,
        onShowProblems: _revealProblemsPanel,
        onShowExplorer: () => _showSidebarPanel(SidebarPanel.explorer),
        onShowSearch: () => _showSidebarPanel(SidebarPanel.search),
        onShowLibraries: () => _showSidebarPanel(SidebarPanel.libraries),
        onShowInsights: () => unawaited(_openInsights()),
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
        onRunTestAtCursor: () => unawaited(_handleRunTestAtCursor()),
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
            OpenSymbolsIntent: CallbackAction<OpenSymbolsIntent>(
              onInvoke: (_) {
                unawaited(_editorWorkspaceSymbol());
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
            OpenPreferencesIntent: CallbackAction<OpenPreferencesIntent>(
              onInvoke: (_) {
                _openPreferences();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: context.palette.background,
              body: Stack(
                children: [
                  Column(
                    children: [
                      if (_centerView != _CenterView.welcome)
                        ValueListenableBuilder<int>(
                          valueListenable: _execution.viewEpoch,
                          builder: (context, _, _) => AppToolbar(
                            projectLabel: _chromeContextLabel,
                            recentProjects: _toolbarRecentProjects,
                            selectedProjectId: _selectedProject?.id,
                            onRecentProjectSelected: (project) =>
                                unawaited(_handleOpenRecentProject(project)),
                            onRevealProject: _selectedProject == null
                                ? null
                                : () {
                                    final path = _selectedProject?.path;
                                    if (path == null) return;
                                    unawaited(_revealPathInOs(path));
                                  },
                            onNewProject: () =>
                                unawaited(_handleNewStandaloneProject()),
                            environmentLabel:
                                activeEnvironment?.name ?? 'No environment',
                            environmentNames: _environments
                                .map((item) => item.name)
                                .toList(),
                            selectedEnvironmentName: activeEnvironment?.name,
                            environmentBroken:
                                activeEnvironment?.available == false,
                            onEnvironmentSelected: _handleActivateByName,
                            onCreateEnvironment: _handleCreateEnvironment,
                            onManageEnvironments: _handleManageEnvironments,
                            runConfigurations: _runConfigurations,
                            activeRunConfigurationId: _activeRunConfigurationId,
                            runConfigurationsEnabled:
                                connected && _selectedProject != null,
                            onRunConfigurationSelected: (id) =>
                                unawaited(_handleSelectRunConfiguration(id)),
                            onNewRunConfiguration: () =>
                                unawaited(_handleNewRunConfiguration()),
                            onManageRunConfigurations: () =>
                                unawaited(_handleManageRunConfigurations()),
                            backendConnected: connected,
                            onRun: _handleRunFile,
                            onRunProject: _handleRunProject,
                            onStop: _handleStopExecution,
                            isExecutionRunning: _executionStatus.isActive,
                            isExecutionStopping:
                                _executionStatus == ExecutionStatus.stopping,
                            executionStatusLabel: _executionStatus.label,
                            executionElapsedLabel: _elapsedLabel,
                            onExecutionStatusTap: _revealTests,
                            canRun: _canRunFile,
                            canRunProject: _canRunTests,
                            robotFrameworkReady: _robotFrameworkReady,
                            onOpenWorkspace: () =>
                                unawaited(_handleOpenWorkspace()),
                            onOpenProject: () =>
                                unawaited(_handleOpenProject()),
                            onNewWorkspace: _handleNewWorkspace,
                            onOpenSearch: () =>
                                unawaited(_openCommandPalette()),
                            gitBranchLabel: _git.currentBranch,
                            gitBranches: _git.localBranchNames,
                            onGitBranchSelected: _git.checkout,
                            onGitCreateBranch: _git.createBranch,
                            onGitDeleteBranch: _git.deleteBranch,
                            onGitFetch: () =>
                                _git.runRemote('fetch', _gateway.fetchGit),
                            onGitPull: () =>
                                _git.runRemote('pull', _gateway.pullGit),
                            onGitPush: () =>
                                _git.runRemote('push', _gateway.pushGit),
                            showGitRemoteActions: _git.isRepository,
                          ),
                        ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_centerView != _CenterView.welcome)
                              AppSidebar(
                                activePanel: _activePanel,
                                settingsActive: _showSettingsPage,
                                showBranding: true,
                                onToggleSidebar: _toggleSidebar,
                                onOpenHelp: () => unawaited(_openUserGuide()),
                                onSettings: _showSettingsPage
                                    ? _closePreferences
                                    : _openPreferences,
                                onPanelSelected: (panel) async {
                                  if (!await _prepareLeaveSettings()) return;
                                  setState(() {
                                    _activePanel = panel;
                                    _showSettingsPage = false;
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
                                      _showEnvironmentManager = false;
                                      _showPackageManager = false;
                                      _showPluginManager = false;
                                      _showSourceControl = false;
                                      _showReportsPage = false;
                                      _showDoctorPage = false;
                                      _showInsightsPage = false;
                                      _selectedEnvironment = null;
                                      _selectedPackage = null;
                                      _execution.selectedReport = null;
                                      if (_editorTabs.isNotEmpty &&
                                          _activeEditorPath != null) {
                                        _enterEditor();
                                      }
                                    } else if (panel == SidebarPanel.explorer) {
                                      _showEnvironmentManager = false;
                                      _showPackageManager = false;
                                      _showPluginManager = false;
                                      _showSourceControl = false;
                                      _showReportsPage = false;
                                      _showDoctorPage = false;
                                      _showInsightsPage = false;
                                      _selectedPackage = null;
                                      _execution.selectedReport = null;
                                      if (_editorTabs.isNotEmpty &&
                                          _activeEditorPath != null) {
                                        _enterEditor();
                                      }
                                    } else {
                                      if (panel == SidebarPanel.packages ||
                                          panel == SidebarPanel.plugins ||
                                          panel == SidebarPanel.reports ||
                                          panel == SidebarPanel.doctor ||
                                          panel == SidebarPanel.insights ||
                                          panel == SidebarPanel.sourceControl) {
                                        _showEditorPage = false;
                                      }
                                      // Drop sticky center flags for panels that
                                      // are not the one being selected — otherwise
                                      // e.g. Insights keeps winning over Packages.
                                      if (panel != SidebarPanel.insights) {
                                        _showInsightsPage = false;
                                      }
                                      if (panel != SidebarPanel.packages) {
                                        _showPackageManager = false;
                                      }
                                      if (panel != SidebarPanel.plugins) {
                                        _showPluginManager = false;
                                      }
                                      if (panel != SidebarPanel.sourceControl) {
                                        _showSourceControl = false;
                                      }
                                      if (panel != SidebarPanel.reports) {
                                        _showReportsPage = false;
                                      }
                                      if (panel != SidebarPanel.doctor) {
                                        _showDoctorPage = false;
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
                                  } else if (panel == SidebarPanel.insights) {
                                    unawaited(_openInsights());
                                  } else if (panel == SidebarPanel.tests) {
                                    _loadExecutionHistory();
                                    _loadTestSuites();
                                  } else if (panel == SidebarPanel.libraries) {
                                    unawaited(_libraryExplorer.loadLibraries());
                                  }
                                },
                              ),
                            if (_centerView != _CenterView.welcome &&
                                !_sidePanelCollapsed &&
                                !_showSettingsPage)
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
                                selectedReport: _selectedReport,
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
                                gitFileStatuses: _git.fileStatuses,
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
                                outlineRoot: _editor.documentAnalysis?.root,
                                isLoadingOutline: _loadingOutline,
                                selectedOutlineId:
                                    _editor.activeDocumentSymbol?.id ??
                                    _selectedOutlineSymbol?.id,
                                onOutlineSelect: (symbol) async {
                                  if (!await _prepareLeaveSettings()) return;
                                  setState(() {
                                    _editor.selectedOutlineSymbol = symbol;
                                    _editor.jumpToLine = symbol.line;
                                    _editor.jumpToColumn = symbol.column;
                                    _enterEditor();
                                  });
                                },
                                onContentSearch: (query) =>
                                    _gateway.searchContent(query: query),
                                onOpenContentMatch: (path, line, column) {
                                  unawaited(
                                    _openFile(path, line: line, column: column),
                                  );
                                },
                                libraryExplorerController: _libraryExplorer,
                                onLibraryJumpToSource: (path, line) {
                                  unawaited(_openFile(path, line: line ?? 1));
                                },
                              ),
                            if (_centerView != _CenterView.welcome &&
                                SidePanel.hasSideContent(_activePanel) &&
                                !_sidePanelCollapsed &&
                                !_showSettingsPage)
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
                      if (_centerView != _CenterView.welcome)
                        BottomPanel(
                          problems: _workspaceProblems,
                          isLoadingProblems: false,
                          problemCount: _workspaceProblems.length,
                          workingDirectory:
                              _activeWorkspace?.path ?? _selectedProject?.path,
                          toggleTerminalToken: _toggleTerminalToken,
                          revealProblemsToken: _revealProblemsToken,
                          onProblemSelected: _handleProblemSelected,
                          onProblemQuickFix: _handleProblemQuickFix,
                        ),
                      if (_centerView != _CenterView.welcome)
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
                          notification: _footerNotice ?? _liveNotification,
                          backendUnavailable: !connected,
                        ),
                    ],
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black38,
                      child: const TimedLoadingIndicator(),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
      _CenterView.editor || _CenterView.execution => _buildEditorOrExecution(),
      _CenterView.settings => PreferencesPage(
        controller: _settings,
        leaveBinding: _preferencesLeave,
      ),
      _CenterView.welcome => WelcomeScreen(
        recentWorkspaces: _recentWorkspaces,
        recentProjects: _recentProjects,
        isLoadingRecent: _loadingRecent,
        showBranding: true,
        onNewWorkspace: _handleNewWorkspace,
        onOpenWorkspace: _handleOpenWorkspace,
        onOpenProject: _handleOpenProject,
        onOpenRecentWorkspace: _handleOpenRecentWorkspace,
        onOpenRecentProject: _handleOpenRecentProject,
        onNewProject: _handleNewStandaloneProject,
        onImportProject: null,
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
        onImportRequirements: _handleImportRequirements,
        onExportRequirements: _handleExportRequirements,
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
        status: _git.status,
        branches: _git.branches,
        history: _git.history,
        selectedCommit: _git.selectedCommit,
        commitDetail: _git.selectedCommitDetail,
        diff: _git.diff,
        selectedFiles: _git.selectedFiles,
        selectedDiffFile: _git.selectedDiffFile,
        commitController: _git.commitController,
        isLoading: _git.loading,
        isBusy: _git.busy,
        isLoadingHistory: _git.loadingHistory,
        isLoadingDiff: _git.loadingDiff,
        onRefresh: _git.refresh,
        onInit: _git.initRepository,
        onToggleFile: _git.toggleFile,
        onSelectDiffFile: _git.loadDiff,
        onCommitAll: () => _handleGitCommit(),
        onCommitSelected: () =>
            _handleGitCommit(files: _git.selectedFiles.toList()),
        onSelectCommit: _git.selectCommit,
        onRefreshHistory: _git.loadHistory,
        onFetch: () => _git.runRemote('fetch', _gateway.fetchGit),
        onPull: () => _git.runRemote('pull', _gateway.pullGit),
        onPush: () => _git.runRemote('push', _gateway.pushGit),
        onCheckoutBranch: _git.checkout,
        onCreateBranch: _git.createBranch,
        onDeleteBranch: _git.deleteBranch,
        onAddRemote: () => unawaited(_handleAddGitRemote()),
        onEditIdentity: () => unawaited(_handleEditGitIdentity()),
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
      _CenterView.reports => ReportsPage(
        isLoading: _loadingReports,
        dashboard: _reportsDashboard,
        isLoadingDashboard: _loadingDashboard,
        selected: _selectedReport,
        failedTests: _reportFailedTests,
        isLoadingFailures: _loadingReportFailures,
        failuresReady: _reportFailuresReady,
        onJumpToFailedTest: (failure) {
          unawaited(
            _openFile(
              failure.source,
              line: failure.line,
              column: failure.column,
            ),
          );
        },
        onRerunFailedTest: (failure) {
          unawaited(_handleRerunFailedTest(failure));
        },
        onRefresh: _loadReports,
        onOpenXml: _openReportXml,
        onOpenLog: _openReportLog,
        onOpenReport: _openReportHtml,
        onReveal: _revealReport,
        onDelete: _deleteSelectedReport,
      ),
      _CenterView.doctor => DoctorPage(
        key: _doctorPageKey,
        gateway: _gateway,
        onJumpToSource: (path, {line, column}) {
          unawaited(_openFile(path, line: line, column: column));
        },
      ),
      _CenterView.insights => InsightsPage(
        insights: _insights,
        isLoading: _loadingInsights,
        loadError: _insightsError,
        onRefresh: () => unawaited(_loadInsights()),
        onRebuildIndex: () => unawaited(_rebuildIndex()),
        onOpenFile: (path) => unawaited(_openFile(path)),
        onOpenRun: (runId) => unawaited(_openInsightsRun(runId)),
        onRerunFile: (path) => unawaited(_rerunInsightsFile(path)),
        onLoadLastFailureName: _loadInsightsLastFailureName,
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

  /// Keep editor and Tests mounted so switching during a run does not dispose
  /// tab tooltips / autocomplete overlays (that paints a one-frame red ErrorWidget).
  Widget _buildEditorOrExecution() {
    return IndexedStack(
      index: _centerView == _CenterView.execution ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        _buildEditorPage(),
        ValueListenableBuilder<int>(
          valueListenable: _execution.viewEpoch,
          builder: (context, _, _) => _buildExecutionPage(),
        ),
      ],
    );
  }

  Widget _buildExecutionPage() {
    return ExecutionPage(
      consoleLines: _executionLines,
      status: _executionStatus,
      currentRun: _currentExecution,
      liveSuite: _execution.liveSuite,
      liveTest: _execution.liveTest,
      liveKeyword: _execution.liveKeyword,
      elapsedLabel: _elapsedLabel,
      failedTests: _failedTests,
      isLoadingFailures: _loadingFailures,
      onJumpToFailedTest: (failure) {
        unawaited(
          _openFile(failure.source, line: failure.line, column: failure.column),
        );
      },
      onRerunFailedTest: (failure) {
        unawaited(_handleRerunFailedTest(failure));
      },
    );
  }

  Widget _buildEditorPage() {
    return EditorPage(
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
      onBreadcrumbTap: _onBreadcrumbTap,
      completionItems: _completionItems,
      diagnostics: _editorDiagnostics,
      hoverTooltip: _hoverTooltip,
      peekDefinition: _peekDefinition,
      jumpToLine: _jumpToLine,
      jumpToColumn: _jumpToColumn,
      onJumpApplied: () {
        if (_editor.jumpToLine == null && _editor.jumpToColumn == null) {
          return;
        }
        setState(() {
          _editor.jumpToLine = null;
          _editor.jumpToColumn = null;
        });
      },
      foldingRanges: _editor.documentAnalysis?.foldingRanges ?? const [],
      runnableTests: runnableTestsFromOutline(
        _editor.documentAnalysis?.root,
        filePath: _activeEditorPath,
      ),
      onRunTest: (test) {
        final path = _activeEditorPath;
        if (path == null) return;
        unawaited(_handleRunSingleTest(file: path, name: test.name));
      },
      runTestsEnabled: _canRunTests && !_executionStatus.isActive,
      fontSize: _settings.editor.fontSize.toDouble(),
      fontFamily: _settings.editor.fontFamily,
      tabWidth: _settings.editor.tabWidth,
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
      onViewportChanged: _editor.onViewportChanged,
      onCompletionAccepted: _editor.recordCompletionUsage,
    );
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
      color: context.palette.background,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 40,
                color: context.palette.textMuted,
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
