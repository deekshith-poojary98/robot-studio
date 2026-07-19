import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/main.dart';
import 'package:robot_studio/presentation/environment/create_environment_dialog.dart';
import 'package:robot_studio/presentation/environment/delete_environment_dialog.dart';
import 'package:robot_studio/presentation/environment/environment_manager_page.dart';
import 'package:robot_studio/presentation/execution/execution_console.dart';
import 'package:robot_studio/presentation/execution/execution_history_list.dart';
import 'package:robot_studio/presentation/packages/package_manager_page.dart';
import 'package:robot_studio/presentation/packages/search_packages_dialog.dart';
import 'package:robot_studio/presentation/packages/uninstall_package_dialog.dart';
import 'package:robot_studio/presentation/project/import_project_dialog.dart';
import 'package:robot_studio/presentation/project/new_project_dialog.dart';
import 'package:robot_studio/presentation/shell/app_shell.dart';
import 'package:robot_studio/presentation/toolbar/app_toolbar.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';
import 'package:robot_studio/presentation/workspace/welcome_screen.dart';
import 'package:robot_studio/presentation/workspace/workspace_explorer.dart';

void main() {
  testWidgets('Welcome screen shows recent workspaces and projects', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeScreen(
            recentWorkspaces: [
              WorkspaceInfo(
                id: '1',
                name: 'Demo Workspace',
                path: '/tmp/Demo Workspace',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ],
            recentProjects: [
              ProjectInfo(
                id: 'p1',
                workspaceId: '1',
                name: 'API Suite',
                path: '/tmp/API',
                type: ProjectType.api,
                createdAt: DateTime.utc(2026, 1, 2),
              ),
            ],
            isLoadingRecent: false,
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Robot Studio'), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('Demo Workspace'), findsOneWidget);
    expect(find.text('API Suite'), findsOneWidget);
    expect(find.text('New Workspace'), findsOneWidget);
  });

  testWidgets('Welcome screen fits short window heights', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeScreen(
            recentWorkspaces: const [],
            recentProjects: const [],
            isLoadingRecent: false,
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Robot Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Project dialog validates name', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showNewProjectDialog(
      tester.element(find.byType(SizedBox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Project'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Project name is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      'My Project',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result?.name, 'My Project');
    expect(result?.type, ProjectType.browser);
  });

  testWidgets('Import Project dialog validates path', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showImportProjectDialog(
      tester.element(find.byType(SizedBox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Import Project'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(find.text('Project path is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project path'),
      '/tmp/robot',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(await future, '/tmp/robot');
  });

  testWidgets('Project explorer lists projects and environments', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var newTapped = false;
    var importTapped = false;
    ProjectInfo? selected;
    EnvironmentInfo? selectedEnv;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: WorkspaceExplorer(
              workspace: WorkspaceInfo(
                id: 'w1',
                name: 'WS',
                path: '/tmp/WS',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              projects: [
                ProjectInfo(
                  id: 'p1',
                  workspaceId: 'w1',
                  name: 'Demo Project',
                  path: '/tmp/WS/Projects/Demo Project',
                  type: ProjectType.browser,
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
              isLoadingProjects: false,
              selectedProject: null,
              onSelectProject: (project) => selected = project,
              onNewProject: () => newTapped = true,
              onImportProject: () => importTapped = true,
              environments: [
                EnvironmentInfo(
                  id: 'e1',
                  workspaceId: 'w1',
                  name: 'robot-3.12',
                  path: '/tmp/WS/Environments/robot-3.12',
                  pythonVersion: '3.12',
                  pythonExecutable: '/tmp/WS/Environments/robot-3.12/bin/python',
                  pipExecutable: '/tmp/WS/Environments/robot-3.12/bin/pip',
                  createdAt: DateTime.utc(2026, 1, 1),
                  active: true,
                  robotVersion: '7.0',
                  packageCount: 12,
                ),
              ],
              onSelectEnvironment: (environment) => selectedEnv = environment,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Demo Project'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.text('Package Manager'), findsOneWidget);
    expect(find.text('robot-3.12 ●'), findsOneWidget);

    await tester.tap(find.byTooltip('New Project'));
    await tester.pump();
    expect(newTapped, isTrue);

    await tester.tap(find.byTooltip('Import Project'));
    await tester.pump();
    expect(importTapped, isTrue);

    await tester.tap(find.text('Demo Project'));
    await tester.pump();
    expect(selected?.name, 'Demo Project');

    await tester.tap(find.text('robot-3.12 ●'));
    await tester.pump();
    expect(selectedEnv?.name, 'robot-3.12');
  });

  testWidgets('Create Environment dialog validates fields', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showCreateEnvironmentDialog(
      tester.element(find.byType(SizedBox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Environment'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Environment name is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Environment name'),
      'robot-3.12',
    );
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Python interpreter is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Python interpreter'),
      '/usr/bin/python3',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result?.name, 'robot-3.12');
    expect(result?.pythonInterpreter, '/usr/bin/python3');
    expect(result?.installRobot, isTrue);
  });

  testWidgets('Environment manager lists environments', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentManagerPage(
            environments: [
              EnvironmentInfo(
                id: 'e1',
                workspaceId: 'w1',
                name: 'robot-3.12',
                path: '/tmp/robot-3.12',
                pythonVersion: '3.12',
                pythonExecutable: '/tmp/robot-3.12/bin/python',
                pipExecutable: '/tmp/robot-3.12/bin/pip',
                createdAt: DateTime.utc(2026, 1, 1),
                active: true,
                robotVersion: '7.1',
                packageCount: 8,
              ),
            ],
            isLoading: false,
            sort: EnvironmentSort.active,
            selected: null,
            onSortChanged: (_) {},
            onSelect: (_) {},
            onCreate: () {},
            onImport: () {},
            onActivate: (_) {},
            onClone: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Environment Manager'), findsOneWidget);
    expect(find.text('robot-3.12'), findsOneWidget);
    expect(find.textContaining('Python 3.12'), findsOneWidget);
    expect(find.text('Active'), findsWidgets);
  });

  testWidgets('Delete dialog blocks active environment', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showDeleteEnvironmentDialog(
      tester.element(find.byType(SizedBox)),
      environment: EnvironmentInfo(
        id: 'e1',
        workspaceId: 'w1',
        name: 'active-env',
        path: '/tmp/active-env',
        pythonVersion: '3.12',
        pythonExecutable: '/tmp/active-env/bin/python',
        pipExecutable: '/tmp/active-env/bin/pip',
        createdAt: DateTime.utc(2026, 1, 1),
        active: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete Environment'), findsOneWidget);
    expect(find.textContaining('cannot be deleted'), findsOneWidget);

    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(deleteButton.onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('App shell renders welcome screen via gateway', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RobotStudioApp(
        home: AppShell(gateway: _FakeTransportGateway()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Robot Studio'), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('Activation flow via environment manager', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = _FakeTransportGateway(withWorkspace: true);
    EnvironmentInfo? activated;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnvironmentManagerPage(
            environments: await gateway.listEnvironments(),
            isLoading: false,
            sort: EnvironmentSort.active,
            selected: null,
            onSortChanged: (_) {},
            onSelect: (_) {},
            onCreate: () {},
            onImport: () {},
            onActivate: (environment) async {
              activated = await gateway.activateEnvironment(environment.id);
            },
            onClone: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('robot-alt'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Activate'));
    await tester.pump();

    expect(gateway.activatedId, 'e2');
    expect(activated?.name, 'robot-alt');
    expect(activated?.active, isTrue);
  });

  testWidgets('Package manager lists packages and robot status', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PackageManagerPage(
            packages: const [
              PackageInfo(
                name: 'robotframework',
                version: '7.0',
                latestVersion: '7.1',
                summary: 'Generic automation framework',
                updateAvailable: true,
              ),
            ],
            isLoading: false,
            sort: PackageSort.name,
            query: '',
            selected: null,
            robotInstalled: true,
            robotVersion: '7.0',
            hasActiveEnvironment: true,
            onQueryChanged: (_) {},
            onSortChanged: (_) {},
            onRefresh: () {},
            onSearchPyPI: () {},
            onSelect: (_) {},
            onUpdate: (_) {},
            onUninstall: (_) {},
            onInstallRobot: () {},
          ),
        ),
      ),
    );

    expect(find.text('Package Manager'), findsOneWidget);
    expect(find.text('robotframework'), findsOneWidget);
    expect(find.textContaining('Robot Framework 7.0'), findsOneWidget);
    expect(find.text('Update'), findsWidgets);
  });

  testWidgets('Search PyPI dialog returns selected package', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showSearchPackagesDialog(
      tester.element(find.byType(SizedBox)),
      onSearch: (query) async => [
        PackageSearchResult(
          name: 'robotframework-browser',
          latestVersion: '18.0.0',
          summary: 'Hit for $query',
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Package name'),
      'browser',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('robotframework-browser'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    final selected = await future;
    expect(selected?.name, 'robotframework-browser');
  });

  testWidgets('Uninstall package dialog confirms', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showUninstallPackageDialog(
      tester.element(find.byType(SizedBox)),
      package: const PackageInfo(name: 'six', version: '1.16.0'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uninstall Package'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('Toolbar shows Robot Framework status badge', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            panelTitle: 'Explorer',
            workspaceLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            robotFrameworkInstalled: false,
            backendConnected: true,
            backendVersion: '0.1.0',
            onInstallRobotFramework: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Robot Framework Missing'), findsOneWidget);
  });

  testWidgets('Execution console shows streamed lines and empty state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExecutionConsole(lines: [])),
      ),
    );
    expect(find.text('Execution output will appear here.'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionConsole(
            lines: [
              '[INFO] Loading SeleniumLibrary',
              '[PASS] Verify Login',
              '[FAIL] Verify Checkout',
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('[INFO] Loading SeleniumLibrary'), findsOneWidget);
    expect(find.text('[PASS] Verify Login'), findsOneWidget);
    expect(find.text('[FAIL] Verify Checkout'), findsOneWidget);
  });

  testWidgets('Toolbar enables Run and disables Stop when idle', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var runTapped = false;
    var stopTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            panelTitle: 'Explorer',
            workspaceLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
            backendVersion: '0.1.0',
            isExecutionRunning: false,
            executionStatusLabel: 'Idle',
            onRun: () => runTapped = true,
            onRunProject: () {},
            onStop: () => stopTapped = true,
          ),
        ),
      ),
    );

    final runButton = tester.widget<ToolbarButton>(
      find.widgetWithText(ToolbarButton, 'RUN'),
    );
    final stopButton = tester.widget<ToolbarButton>(
      find.widgetWithText(ToolbarButton, 'STOP'),
    );
    expect(runButton.onTap, isNotNull);
    expect(stopButton.onTap, isNull);

    await tester.tap(find.widgetWithText(ToolbarButton, 'RUN'));
    await tester.pump();
    expect(runTapped, isTrue);

    await tester.tap(find.widgetWithText(ToolbarButton, 'STOP'));
    await tester.pump();
    expect(stopTapped, isFalse);
  });

  testWidgets('Toolbar disables Run and enables Stop when running', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var stopTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            panelTitle: 'Explorer',
            workspaceLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
            backendVersion: '0.1.0',
            isExecutionRunning: true,
            executionStatusLabel: 'Running',
            executionElapsedLabel: '1.2s',
            onRun: () {},
            onRunProject: () {},
            onStop: () => stopTapped = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('Running'), findsWidgets);
    expect(find.textContaining('1.2s'), findsOneWidget);

    final runButton = tester.widget<ToolbarButton>(
      find.widgetWithText(ToolbarButton, 'RUN'),
    );
    final stopButton = tester.widget<ToolbarButton>(
      find.widgetWithText(ToolbarButton, 'STOP'),
    );
    expect(runButton.onTap, isNull);
    expect(stopButton.onTap, isNotNull);

    await tester.tap(find.widgetWithText(ToolbarButton, 'STOP'));
    await tester.pump();
    expect(stopTapped, isTrue);
  });

  testWidgets('Execution history list shows runs and empty state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionHistoryList(runs: []),
        ),
      ),
    );
    expect(find.text('No executions yet.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionHistoryList(
            runs: [
              ExecutionInfo(
                id: 'run-1',
                workspaceId: 'ws',
                projectId: 'p1',
                environmentId: 'e1',
                projectName: 'Login Suite',
                suite: 'tests/login.robot',
                status: ExecutionStatus.finished,
                startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
                durationMs: 1500,
                exitCode: 0,
              ),
              ExecutionInfo(
                id: 'run-2',
                workspaceId: 'ws',
                projectId: 'p1',
                environmentId: 'e1',
                projectName: 'Checkout',
                suite: 'tests/checkout.robot',
                status: ExecutionStatus.failed,
                startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
                durationMs: 2200,
                exitCode: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Login Suite'), findsOneWidget);
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('FINISHED'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
  });

  testWidgets('Welcome screen shows recent runs card', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeScreen(
            recentWorkspaces: const [],
            recentProjects: const [],
            isLoadingRecent: false,
            recentRuns: [
              ExecutionInfo(
                id: 'run-1',
                workspaceId: 'ws',
                projectId: 'p1',
                environmentId: 'e1',
                projectName: 'API Suite',
                suite: 'tests/api.robot',
                status: ExecutionStatus.finished,
                startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
                durationMs: 900,
                exitCode: 0,
              ),
            ],
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent Runs'), findsOneWidget);
    expect(find.textContaining('tests/api.robot'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
  });
}

class _FakeTransportGateway implements TransportGateway {
  _FakeTransportGateway({this.withWorkspace = false});

  final bool withWorkspace;
  String? activatedId;

  List<EnvironmentInfo> _environments = [
    EnvironmentInfo(
      id: 'e1',
      workspaceId: '1',
      name: 'robot-main',
      path: '/tmp/WS/Environments/robot-main',
      pythonVersion: '3.12',
      pythonExecutable: '/tmp/WS/Environments/robot-main/bin/python',
      pipExecutable: '/tmp/WS/Environments/robot-main/bin/pip',
      createdAt: DateTime.utc(2026, 1, 1),
      active: true,
      robotVersion: '7.0',
      packageCount: 5,
    ),
    EnvironmentInfo(
      id: 'e2',
      workspaceId: '1',
      name: 'robot-alt',
      path: '/tmp/WS/Environments/robot-alt',
      pythonVersion: '3.13',
      pythonExecutable: '/tmp/WS/Environments/robot-alt/bin/python',
      pipExecutable: '/tmp/WS/Environments/robot-alt/bin/pip',
      createdAt: DateTime.utc(2026, 1, 2),
      active: false,
      packageCount: 3,
    ),
  ];

  @override
  Future<HealthResponse> health() async {
    return const HealthResponse(
      status: 'ok',
      version: '0.1.0',
      modules: ['workspace', 'project', 'environment'],
    );
  }

  @override
  Future<WorkspaceInfo> createWorkspace({
    required String name,
    required String location,
  }) async {
    return WorkspaceInfo(
      id: 'new',
      name: name,
      path: '$location/$name',
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<WorkspaceInfo> openWorkspace(String path) async {
    return WorkspaceInfo(
      id: '1',
      name: 'Alpha',
      path: path,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<List<WorkspaceInfo>> listRecentWorkspaces() async {
    return [
      WorkspaceInfo(
        id: '1',
        name: 'Alpha',
        path: '/tmp/Alpha',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<ProjectInfo> createProject({
    required String name,
    required ProjectType type,
  }) async {
    return ProjectInfo(
      id: 'p-new',
      workspaceId: '1',
      name: name,
      path: '/tmp/$name',
      type: type,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<ProjectInfo> importProject(String path) async {
    return ProjectInfo(
      id: 'p-imp',
      workspaceId: '1',
      name: 'Imported',
      path: path,
      type: ProjectType.imported,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<List<ProjectInfo>> listProjects() async => [];

  @override
  Future<ProjectInfo> openProject(String projectId) async {
    return ProjectInfo(
      id: projectId,
      workspaceId: '1',
      name: 'Opened',
      path: '/tmp/Opened',
      type: ProjectType.empty,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<List<ProjectInfo>> listRecentProjects() async {
    return [
      ProjectInfo(
        id: 'p1',
        workspaceId: '1',
        name: 'Beta Project',
        path: '/tmp/Beta',
        type: ProjectType.selenium,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<EnvironmentInfo>> listEnvironments({
    EnvironmentSort sort = EnvironmentSort.active,
  }) async {
    if (!withWorkspace) return [];
    return List<EnvironmentInfo>.from(_environments);
  }

  @override
  Future<EnvironmentInfo> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  }) async {
    final environment = EnvironmentInfo(
      id: 'e-new',
      workspaceId: '1',
      name: name,
      path: '/tmp/$name',
      pythonVersion: '3.12',
      pythonExecutable: '/tmp/$name/bin/python',
      pipExecutable: '/tmp/$name/bin/pip',
      createdAt: DateTime.utc(2026, 1, 1),
      active: _environments.isEmpty,
    );
    _environments = [..._environments, environment];
    return environment;
  }

  @override
  Future<EnvironmentInfo> importEnvironment(String path) async {
    return EnvironmentInfo(
      id: 'e-imp',
      workspaceId: '1',
      name: 'imported',
      path: path,
      pythonVersion: '3.12',
      pythonExecutable: '$path/bin/python',
      pipExecutable: '$path/bin/pip',
      createdAt: DateTime.utc(2026, 1, 1),
      active: false,
    );
  }

  @override
  Future<EnvironmentInfo> activateEnvironment(String environmentId) async {
    activatedId = environmentId;
    _environments = [
      for (final item in _environments)
        EnvironmentInfo(
          id: item.id,
          workspaceId: item.workspaceId,
          name: item.name,
          path: item.path,
          pythonVersion: item.pythonVersion,
          pythonExecutable: item.pythonExecutable,
          pipExecutable: item.pipExecutable,
          robotExecutable: item.robotExecutable,
          createdAt: item.createdAt,
          active: item.id == environmentId,
          robotVersion: item.robotVersion,
          packageCount: item.packageCount,
          platform: item.platform,
          architecture: item.architecture,
        ),
    ];
    return _environments.firstWhere((item) => item.id == environmentId);
  }

  @override
  Future<EnvironmentInfo> getEnvironment(String environmentId) async {
    return _environments.firstWhere((item) => item.id == environmentId);
  }

  @override
  Future<EnvironmentInfo> cloneEnvironment({
    required String environmentId,
    required String name,
  }) async {
    return EnvironmentInfo(
      id: 'e-clone',
      workspaceId: '1',
      name: name,
      path: '/tmp/$name',
      pythonVersion: '3.12',
      pythonExecutable: '/tmp/$name/bin/python',
      pipExecutable: '/tmp/$name/bin/pip',
      createdAt: DateTime.utc(2026, 1, 1),
      active: false,
    );
  }

  @override
  Future<void> deleteEnvironment({
    required String environmentId,
    bool deleteFiles = false,
  }) async {
    _environments =
        _environments.where((item) => item.id != environmentId).toList();
  }

  List<PackageInfo> _packages = [
    const PackageInfo(
      name: 'robotframework',
      version: '7.0',
      latestVersion: '7.1',
      summary: 'Generic automation framework',
      updateAvailable: true,
    ),
    const PackageInfo(
      name: 'six',
      version: '1.16.0',
      latestVersion: '1.16.0',
      summary: 'Python 2 and 3 compatibility utilities',
    ),
  ];

  @override
  Future<PackageListResult> listPackages({
    String? query,
    PackageSort sort = PackageSort.name,
  }) async {
    var items = List<PackageInfo>.from(_packages);
    if (query != null && query.isNotEmpty) {
      items = items
          .where((item) => item.name.contains(query.toLowerCase()))
          .toList();
    }
    return PackageListResult(
      packages: items,
      robotFrameworkInstalled: items.any(
        (item) => item.name.toLowerCase() == 'robotframework',
      ),
      robotFrameworkVersion: '7.0',
      environmentId: 'e1',
      environmentName: 'robot-main',
    );
  }

  @override
  Future<List<PackageSearchResult>> searchPackages(String query) async {
    return [
      PackageSearchResult(
        name: 'robotframework-browser',
        latestVersion: '18.0.0',
        summary: 'Search hit for $query',
      ),
    ];
  }

  @override
  Future<PackageInfo> getPackage(String name) async {
    return _packages.firstWhere((item) => item.name == name);
  }

  @override
  Future<PackageOperationResult> installPackage(String name) async {
    final package = PackageInfo(
      name: name,
      version: '1.0.0',
      latestVersion: '1.0.0',
      summary: 'Installed $name',
    );
    _packages = [..._packages, package];
    return PackageOperationResult(
      package: package,
      logs: ['Installing $name', 'Successfully installed $name'],
      robotFrameworkInstalled:
          name.toLowerCase() == 'robotframework' ||
          _packages.any((item) => item.name.toLowerCase() == 'robotframework'),
      robotFrameworkVersion: '7.0',
    );
  }

  @override
  Future<PackageOperationResult> updatePackage(String name) async {
    final package = PackageInfo(
      name: name,
      version: '7.1',
      latestVersion: '7.1',
      summary: 'Updated $name',
    );
    _packages = [
      for (final item in _packages)
        if (item.name == name) package else item,
    ];
    return PackageOperationResult(
      package: package,
      logs: ['Updating $name', 'Successfully updated $name'],
      robotFrameworkInstalled: true,
      robotFrameworkVersion: '7.1',
    );
  }

  @override
  Future<PackageOperationResult> uninstallPackage(String name) async {
    _packages = _packages.where((item) => item.name != name).toList();
    return PackageOperationResult(
      logs: ['Uninstalling $name', 'Successfully uninstalled $name'],
      robotFrameworkInstalled: _packages.any(
        (item) => item.name.toLowerCase() == 'robotframework',
      ),
    );
  }

  @override
  Future<ExecutionInfo> runFile({String? file}) async {
    return ExecutionInfo(
      id: 'run-file',
      workspaceId: '1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: file ?? 'tests',
      status: ExecutionStatus.idle,
      startedAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<ExecutionInfo> runProject() async {
    return ExecutionInfo(
      id: 'run-project',
      workspaceId: '1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: 'project',
      status: ExecutionStatus.idle,
      startedAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<ExecutionInfo> stopExecution() async {
    return ExecutionInfo(
      id: 'run-stop',
      workspaceId: '1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: 'tests',
      status: ExecutionStatus.cancelled,
      startedAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<ExecutionStatusInfo> getExecutionStatus() async {
    return const ExecutionStatusInfo(status: ExecutionStatus.idle);
  }

  @override
  Future<List<ExecutionInfo>> listExecutionHistory() async => [];
}
