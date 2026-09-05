import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/main.dart';
import 'package:robot_studio/presentation/editor/editor_page.dart';
import 'package:robot_studio/presentation/editor/editor_tabs_bar.dart';
import 'package:robot_studio/presentation/environment/create_environment_dialog.dart';
import 'package:robot_studio/presentation/environment/delete_environment_dialog.dart';
import 'package:robot_studio/presentation/environment/environment_manager_page.dart';
import 'package:robot_studio/presentation/execution/execution_console.dart';
import 'package:robot_studio/presentation/packages/already_installed_package_dialog.dart';
import 'package:robot_studio/presentation/packages/package_manager_page.dart';
import 'package:robot_studio/presentation/packages/search_packages_dialog.dart';
import 'package:robot_studio/presentation/packages/uninstall_package_dialog.dart';
import 'package:robot_studio/presentation/project/import_project_dialog.dart';
import 'package:robot_studio/presentation/project/new_project_dialog.dart';
import 'package:robot_studio/presentation/reports/delete_run_dialog.dart';
import 'package:robot_studio/presentation/reports/reports_page.dart';
import 'package:robot_studio/presentation/reports/run_details_panel.dart';
import 'package:robot_studio/presentation/search/index_status_card.dart';
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
                createdAt: DateTime.utc(2026, 1, 2),
              ),
            ],
            isLoadingRecent: false,
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenProject: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('welcome.wordmark')), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('Demo Workspace'), findsOneWidget);
    expect(find.text('API Suite'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('New Workspace'), findsOneWidget);
    expect(find.byKey(const Key('welcome.backend-unavailable')), findsNothing);

    // Recent Projects appear before Recent Workspaces in the welcome layout.
    final projectsOffset = tester.getTopLeft(find.text('Recent Projects')).dy;
    final workspacesOffset = tester
        .getTopLeft(find.text('Recent Workspaces'))
        .dy;
    expect(projectsOffset < workspacesOffset, isTrue);
  });

  testWidgets('Welcome screen shows backend unavailable hint', (
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
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenProject: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
            backendUnavailable: true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('welcome.backend-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('make backend'), findsOneWidget);
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
            onOpenProject: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('welcome.wordmark')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Project dialog validates name', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showNewProjectDialog(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();

    expect(find.text('New Project'), findsOneWidget);
    final createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(createButton.onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      'My Project',
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result, 'My Project');
  });

  testWidgets('New Project dialog collects name and location', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showNewStandaloneProjectDialog(
      tester.element(find.byType(SizedBox)),
      initialLocation: '/Users/demo/robot-files',
    );
    await tester.pumpAndSettle();

    // Location is prefilled and browsable — no bare folder picker up front.
    expect(find.text('/Users/demo/robot-files'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Browse…'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      'Amazon',
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result?.name, 'Amazon');
    expect(result?.location, '/Users/demo/robot-files');
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

  testWidgets(
    'Project explorer lists projects without env/package/report sections',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var newTapped = false;
      var importTapped = false;
      ProjectInfo? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 800,
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
                    createdAt: DateTime.utc(2026, 1, 1),
                  ),
                ],
                isLoadingProjects: false,
                selectedProject: null,
                onSelectProject: (project) => selected = project,
                onNewProject: () => newTapped = true,
                onImportProject: () => importTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Demo Project'), findsOneWidget);
      expect(find.text('Shared'), findsNothing);
      expect(find.text('Environments'), findsNothing);
      expect(find.text('Packages'), findsNothing);
      expect(find.text('Reports'), findsNothing);

      await tester.tap(find.byTooltip('New Project'));
      await tester.pump();
      expect(newTapped, isTrue);

      await tester.tap(find.byTooltip('Import Project'));
      await tester.pump();
      expect(importTapped, isTrue);

      await tester.tap(find.text('Demo Project'));
      await tester.pump();
      expect(selected?.name, 'Demo Project');
    },
  );

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
      loadInterpreters: () async => const [
        PythonInterpreterInfo(
          path: '/usr/bin/python3',
          version: '3.12.0',
          displayName: 'Python 3.12.0 — /usr/bin/python3',
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Environment'), findsOneWidget);
    expect(find.text('Available interpreters'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(find.text('Environment name is required'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Environment name'),
      'robot-3.12',
    );
    // Interpreter is preselected from the discovered list.
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result?.name, 'robot-3.12');
    expect(result?.pythonInterpreter, '/usr/bin/python3');
    expect(result?.installRobot, isTrue);
  });

  testWidgets('Create Environment dialog keeps custom browse path', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showCreateEnvironmentDialog(
      tester.element(find.byType(SizedBox)),
      loadInterpreters: () async => const [
        PythonInterpreterInfo(
          path: '/usr/bin/python3',
          version: '3.12.0',
          displayName: 'Python 3.12.0 — /usr/bin/python3',
        ),
      ],
    );
    await tester.pumpAndSettle();

    // Open dropdown then choose custom path.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom path…').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Environment name'),
      'custom-env',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Python interpreter'),
      '/custom/python3',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final result = await future;
    expect(result?.name, 'custom-env');
    expect(result?.pythonInterpreter, '/custom/python3');
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
      RobotStudioApp(home: AppShell(gateway: _FakeTransportGateway())),
    );
    await tester.pumpAndSettle();

    // Toolbar no longer repeats the product name; welcome shows the wordmark.
    expect(find.byKey(const Key('welcome.wordmark')), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('startup restores the last recent project', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = _FakeTransportGateway(
      settings: const AppSettings(
        appearance: AppearanceSettings(restoreLastProject: true),
      ),
    );
    await tester.pumpWidget(RobotStudioApp(home: AppShell(gateway: gateway)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    // Restoring a project schedules staggered loads (git at 800ms). Advance
    // past them so dispose does not trip the pending-timer assertion.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(gateway.openProjectByPathCalls, 1);
    expect(gateway.lastOpenedProjectPath, '/tmp/Beta');
    expect(find.text('Recent Workspaces'), findsNothing);
    expect(find.text('Opened'), findsWidgets);
  });

  testWidgets('startup stays on welcome when restore is disabled', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = _FakeTransportGateway();
    await tester.pumpWidget(RobotStudioApp(home: AppShell(gateway: gateway)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(gateway.openProjectByPathCalls, 0);
    expect(find.text('Recent Projects'), findsOneWidget);
  });

  testWidgets('startup restore failure stays on welcome without a dialog', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = _FakeTransportGateway(
      settings: const AppSettings(
        appearance: AppearanceSettings(restoreLastProject: true),
      ),
      openProjectByPathError: Exception('path gone'),
    );
    await tester.pumpWidget(RobotStudioApp(home: AppShell(gateway: gateway)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(gateway.openProjectByPathCalls, 1);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Appearance preference themes the whole app', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<AppPalette> pumpWith(AppThemePreference preference) async {
      // Fully tear down between runs: reusing the tree would keep the previous
      // shell State (so settings never reload), and RobotStudioMenuBar asserts
      // if a second PlatformMenuBar registers while the first is alive.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpWidget(
        RobotStudioApp(
          gateway: _FakeTransportGateway(
            settings: AppSettings(
              appearance: AppearanceSettings(
                theme: preference,
                restoreLastProject: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // MaterialApp lerps theme changes over kThemeAnimationDuration, so a
      // mid-flight frame still reports the outgoing brightness.
      await tester.pump(const Duration(milliseconds: 400));
      return tester.element(find.text('Recent Workspaces')).palette;
    }

    expect(
      (await pumpWith(AppThemePreference.dark)).brightness,
      Brightness.dark,
    );

    // The bug this guards: setting Light stored the preference but nothing
    // consumed it, so every surface stayed on dark constants.
    final light = await pumpWith(AppThemePreference.light);
    expect(light.brightness, Brightness.light);
    expect(light.background, AppPalette.light.background);
    expect(light.textPrimary, AppPalette.light.textPrimary);

    // Catch any surface still painted from a dark token. This is what a
    // half-finished migration looks like: the theme flips but panels don't.
    final darkOnly = <Color>{
      AppPalette.dark.background,
      AppPalette.dark.surface,
      AppPalette.dark.surfaceElevated,
      AppPalette.dark.surfaceHover,
      AppPalette.dark.rail,
      AppPalette.dark.statusBar,
      AppPalette.dark.textPrimary,
    };

    final offenders = <String>[];
    for (final widget in tester.allWidgets) {
      final color = switch (widget) {
        ColoredBox(:final color) => color,
        Material(:final color) => color,
        Container(:final color) => color,
        DecoratedBox(decoration: BoxDecoration(:final color)) => color,
        Text(style: TextStyle(:final color)) => color,
        _ => null,
      };
      if (color != null && darkOnly.contains(color)) {
        offenders.add('${widget.runtimeType} -> $color');
      }
    }
    expect(offenders, isEmpty, reason: 'dark tokens painted in light mode');
  });

  testWidgets('Appearance accent colours the whole app', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<AppPalette> pumpWith(AppAccentPreference accent) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await tester.pumpWidget(
        RobotStudioApp(
          gateway: _FakeTransportGateway(
            settings: AppSettings(
              appearance: AppearanceSettings(
                accent: accent,
                restoreLastProject: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      return tester.element(find.text('Recent Workspaces')).palette;
    }

    final teal = await pumpWith(AppAccentPreference.teal);
    expect(teal.accent, AppPalette.dark.accent);

    final blue = await pumpWith(AppAccentPreference.blue);
    expect(
      blue.accent,
      AppPalette.forAccent(
        AppAccentPreference.blue,
        brightness: Brightness.dark,
      ).accent,
    );
    expect(blue.background, AppPalette.dark.background);
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
    var importRequirementsTapped = false;
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
            hasActiveEnvironment: true,
            onQueryChanged: (_) {},
            onSortChanged: (_) {},
            onRefresh: () {},
            onSearchPyPI: () {},
            onImportRequirements: () => importRequirementsTapped = true,
            onExportRequirements: () {},
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
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('VERSION'), findsOneWidget);
    expect(find.text('7.0'), findsOneWidget);
    expect(find.text('7.1'), findsOneWidget);
    expect(find.textContaining('Robot Framework 7.0'), findsNothing);
    expect(find.byTooltip('Update to 7.1'), findsOneWidget);
    expect(find.byTooltip('Uninstall'), findsOneWidget);
    expect(find.text('Import requirements'), findsOneWidget);
    expect(find.text('Export requirements'), findsOneWidget);
    await tester.tap(find.text('Import requirements'));
    await tester.pump();
    expect(importRequirementsTapped, isTrue);
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
      onLoadVersions: (name) async => PackageVersionList(
        name: name,
        latestVersion: '18.0.0',
        versions: const ['18.0.0', '17.5.0', '16.0.0'],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Package name'),
      'browser',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('robotframework-browser'), findsWidgets);
    // Rows are the selection affordance; no per-result button.
    await tester.tap(find.text('robotframework-browser').last);
    await tester.pumpAndSettle();

    expect(find.text('Version'), findsOneWidget);
    expect(find.textContaining('18.0.0'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    final selected = await future;
    expect(selected?.name, 'robotframework-browser');
    expect(selected?.version, '18.0.0');
  });

  testWidgets('Search PyPI dialog can pick a non-latest version', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showSearchPackagesDialog(
      tester.element(find.byType(SizedBox)),
      onSearch: (query) async => const [
        PackageSearchResult(
          name: 'six',
          latestVersion: '1.16.0',
          summary: 'compat',
        ),
      ],
      onLoadVersions: (name) async => const PackageVersionList(
        name: 'six',
        latestVersion: '1.16.0',
        versions: ['1.16.0', '1.15.0', '1.14.0'],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Package name'),
      'six',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('six').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.15.0').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    await tester.pumpAndSettle();

    final selected = await future;
    expect(selected?.name, 'six');
    expect(selected?.version, '1.15.0');
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

  testWidgets('Already installed dialog offers Force Install', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showAlreadyInstalledPackageDialog(
      tester.element(find.byType(SizedBox)),
      name: 'six',
      version: '1.16.0',
    );
    await tester.pumpAndSettle();

    expect(find.text('Already Installed'), findsOneWidget);
    expect(find.textContaining('already installed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Force Install'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('Already installed dialog Cancel returns false', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showAlreadyInstalledPackageDialog(
      tester.element(find.byType(SizedBox)),
      name: 'six',
      version: '1.16.0',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });

  testWidgets('Toolbar shows environment selector without Robot badge', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
          ),
        ),
      ),
    );

    expect(find.text('robot-main'), findsOneWidget);
    expect(find.textContaining('Robot Framework Missing'), findsNothing);
    expect(find.textContaining('Robot —'), findsNothing);
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
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
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
      find.byKey(const Key('toolbar.run')),
    );
    final stopButton = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.stop')),
    );
    expect(runButton.onTap, isNotNull);
    expect(stopButton.onTap, isNull);

    await tester.tap(find.byKey(const Key('toolbar.run')));
    await tester.pump();
    expect(runTapped, isTrue);

    await tester.tap(find.byKey(const Key('toolbar.stop')));
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
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
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
      find.byKey(const Key('toolbar.run')),
    );
    final stopButton = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.stop')),
    );
    expect(runButton.onTap, isNull);
    expect(stopButton.onTap, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('toolbar.stop')));
    await tester.tap(find.byKey(const Key('toolbar.stop')));
    await tester.pump();
    expect(stopTapped, isTrue);
  });

  testWidgets('Toolbar shows Stopping and disables Stop while winding down', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var stopTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            environmentNames: const ['robot-main'],
            selectedEnvironmentName: 'robot-main',
            backendConnected: true,
            isExecutionRunning: true,
            isExecutionStopping: true,
            executionStatusLabel: 'Stopping',
            executionElapsedLabel: '47.3s',
            onRun: () {},
            onRunProject: () {},
            onStop: () => stopTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('STOPPING'), findsOneWidget);
    expect(find.textContaining('Stopping'), findsWidgets);
    final stopButton = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.stop')),
    );
    expect(stopButton.onTap, isNull);
    await tester.tap(find.byKey(const Key('toolbar.stop')));
    await tester.pump();
    expect(stopTapped, isFalse);
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
            onOpenProject: () {},
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

  testWidgets('Reports page shows dashboard and selected run details', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final run = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: 'tests/demo.robot',
      status: ExecutionStatus.finished,
      startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
      durationMs: 1500,
      exitCode: 0,
      environmentName: 'robot-main',
      robotVersion: '7.0',
      totalTests: 2,
      passed: 2,
      failed: 0,
      skipped: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            isLoading: false,
            dashboard: DashboardSummary(
              totalRuns: 1,
              passRate: 100,
              averageDurationMs: 1500,
              lastRun: run,
              recentRuns: [run],
            ),
            isLoadingDashboard: false,
            selected: run,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('PASS'), findsNothing);
    expect(find.text('Finished'), findsWidgets);
    expect(find.text('Select a run from the Reports panel.'), findsNothing);
    expect(find.text('Total Runs'), findsOneWidget);
    expect(find.text('Pass Rate'), findsOneWidget);
  });

  testWidgets('Reports page shows last run while the list is still loading', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final run = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: 'tests/demo.robot',
      status: ExecutionStatus.finished,
      startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            isLoading: true,
            dashboard: null,
            isLoadingDashboard: true,
            selected: run,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('No run selected'), findsNothing);
  });

  testWidgets('Run details panel shows statistics and artifacts', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunDetailsPanel(
            run: ExecutionInfo(
              id: 'run-1',
              workspaceId: 'ws',
              projectId: 'p1',
              environmentId: 'e1',
              projectName: 'Checkout',
              suite: 'tests/checkout.robot',
              status: ExecutionStatus.failed,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              finishedAt: DateTime.utc(2026, 7, 19, 11, 0, 3),
              durationMs: 3000,
              exitCode: 1,
              environmentName: 'robot-main',
              robotVersion: '7.1',
              totalTests: 3,
              passed: 2,
              failed: 1,
              skipped: 0,
              outputXml: '/tmp/output.xml',
              logHtml: '/tmp/log.html',
              reportHtml: '/tmp/report.html',
              outputDir: '/tmp/Run-1',
            ),
            onOpenXml: () {},
            onOpenLog: () {},
            onOpenReport: () {},
            onReveal: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Artifacts'), findsOneWidget);
    expect(find.text('output.xml'), findsOneWidget);
    expect(find.text('log.html'), findsOneWidget);
    expect(find.text('report.html'), findsOneWidget);
    expect(find.text('Open Log'), findsNothing);
    expect(find.text('Open Report'), findsNothing);
    expect(find.text('Reveal Folder'), findsOneWidget);
    expect(find.text('FAIL'), findsNothing);
  });

  testWidgets('Run details panel shows failed test message', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunDetailsPanel(
            run: ExecutionInfo(
              id: 'run-1',
              workspaceId: 'ws',
              projectId: 'p1',
              environmentId: 'e1',
              projectName: 'Checkout',
              suite: 'tests/checkout.robot',
              status: ExecutionStatus.failed,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              finishedAt: DateTime.utc(2026, 7, 19, 11, 0, 3),
              durationMs: 3000,
              exitCode: 1,
              totalTests: 3,
              passed: 2,
              failed: 1,
              skipped: 0,
            ),
            failedTests: const [
              RunTestFailureInfo(
                runId: 'run-1',
                name: 'Verify Checkout',
                message: 'Element not found: #pay',
                source: 'tests/checkout.robot',
                line: 42,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed Tests'), findsOneWidget);
    expect(find.text('Verify Checkout'), findsOneWidget);
    expect(find.text('Element not found: #pay'), findsOneWidget);
    expect(find.text('Jump to Source'), findsOneWidget);
    expect(find.text('Re-run Test'), findsOneWidget);
  });

  testWidgets('Delete run dialog confirms', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    final future = showDeleteRunDialog(
      tester.element(find.byType(SizedBox)),
      run: ExecutionInfo(
        id: 'run-1',
        workspaceId: 'ws',
        projectId: 'p1',
        environmentId: 'e1',
        projectName: 'Demo',
        suite: 'tests/demo.robot',
        status: ExecutionStatus.finished,
        startedAt: DateTime.utc(2026, 7, 19),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete Run'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('Welcome screen shows run dashboard metrics', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final run = ExecutionInfo(
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeScreen(
            recentWorkspaces: const [],
            recentProjects: const [],
            isLoadingRecent: false,
            workspaceOpen: true,
            dashboard: DashboardSummary(
              totalRuns: 4,
              passRate: 75,
              averageDurationMs: 1200,
              lastRun: run,
              recentRuns: [run],
              recentFailures: const [],
            ),
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenProject: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Pass Rate'), findsWidgets);
    expect(find.textContaining('Total Runs'), findsWidgets);
    expect(find.textContaining('Average'), findsWidgets);
  });

  testWidgets('Index status card shows metrics', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IndexStatusCard(
            status: IndexStatusInfo(
              state: 'ready',
              filesIndexed: 12,
              keywordsIndexed: 45,
              librariesIndexed: 3,
              variablesIndexed: 18,
              lastIndexedAt: DateTime.utc(2026, 7, 19, 14, 30, 0),
            ),
            onRebuild: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Index Status'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('Rebuild'), findsOneWidget);
  });

  testWidgets('Welcome screen shows index status card', (
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
            workspaceOpen: true,
            indexStatus: const IndexStatusInfo(
              state: 'ready',
              filesIndexed: 5,
              keywordsIndexed: 10,
            ),
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenProject: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Index Status'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Run Dashboard'), findsOneWidget);
  });

  testWidgets('EditorTabsBar shows dirty indicator and close', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 120));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var closedPath = '';
    final tabs = [
      EditorTabInfo(
        path: '/tmp/tests/login.robot',
        content: '*** Test Cases ***',
        savedContent: '*** Test Cases ***',
        mtime: 1,
      ),
      EditorTabInfo(
        path: '/tmp/resources/login.resource',
        content: '*** Keywords ***\nChanged',
        savedContent: '*** Keywords ***',
        mtime: 1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorTabsBar(
            tabs: tabs,
            activePath: tabs[1].path,
            onSelect: (_) {},
            onClose: (path) => closedPath = path,
          ),
        ),
      ),
    );

    expect(find.text('login.robot'), findsOneWidget);
    expect(find.text('login.resource'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    expect(closedPath, tabs[1].path);
  });

  testWidgets('EditorPage shows empty state without active tab', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(
            tabs: const [],
            activePath: null,
            wordWrap: true,
            hover: null,
            references: const [],
            statusMessage: null,
            breadcrumb: const EditorBreadcrumbInfo(),
            completionItems: const [],
            diagnostics: const [],
            hoverTooltip: null,
            peekDefinition: null,
            onSelectTab: (_) {},
            onCloseTab: (_) {},
            onContentChanged: (_, _) {},
            onSave: () {},
            onHoverRequest: (_, _) {},
            onHoverExit: () {},
            onCtrlClick: () {},
            onClosePeek: () {},
            onCursorChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('No file open'), findsOneWidget);
  });

  testWidgets('EditorPage opens file via tabs list', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedPath = '';
    final tabs = [
      EditorTabInfo(
        path: '/tmp/tests/login.robot',
        content: '*** Test Cases ***\nLogin',
        savedContent: '*** Test Cases ***\nLogin',
        mtime: 1,
      ),
      EditorTabInfo(
        path: '/tmp/tests/checkout.robot',
        content: '*** Test Cases ***\nCheckout',
        savedContent: '*** Test Cases ***\nCheckout',
        mtime: 1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(
            tabs: tabs,
            activePath: tabs[0].path,
            wordWrap: true,
            hover: null,
            references: const [],
            statusMessage: null,
            breadcrumb: const EditorBreadcrumbInfo(),
            completionItems: const [],
            diagnostics: const [],
            hoverTooltip: null,
            peekDefinition: null,
            onSelectTab: (path) => selectedPath = path,
            onCloseTab: (_) {},
            onContentChanged: (_, _) {},
            onSave: () {},
            onHoverRequest: (_, _) {},
            onHoverExit: () {},
            onCtrlClick: () {},
            onClosePeek: () {},
            onCursorChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('login.robot'), findsOneWidget);
    expect(find.text('checkout.robot'), findsOneWidget);

    await tester.tap(find.text('checkout.robot'));
    await tester.pump();
    expect(selectedPath, tabs[1].path);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('EditorPage shows hover/references side panel without toolbar', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tabs = [
      EditorTabInfo(
        path: '/tmp/tests/login.robot',
        content: '*** Keywords ***\nLogin With Credentials\n    Log    hi\n',
        savedContent:
            '*** Keywords ***\nLogin With Credentials\n    Log    hi\n',
        mtime: 1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(
            tabs: tabs,
            activePath: tabs[0].path,
            wordWrap: true,
            hover: const HoverInfo(
              name: 'Login With Credentials',
              kind: SymbolKind.keyword,
              filePath: '/tmp/tests/login.robot',
              line: 2,
              documentation: 'Logs into the application.',
            ),
            references: const [
              SymbolReferenceInfo(
                name: 'Login With Credentials',
                filePath: '/tmp/tests/checkout.robot',
                line: 8,
                context: 'Login With Credentials',
              ),
            ],
            statusMessage: null,
            breadcrumb: const EditorBreadcrumbInfo(),
            completionItems: const [],
            diagnostics: const [],
            hoverTooltip: null,
            peekDefinition: null,
            onSelectTab: (_) {},
            onCloseTab: (_) {},
            onContentChanged: (_, _) {},
            onSave: () {},
            onHoverRequest: (_, _) {},
            onHoverExit: () {},
            onCtrlClick: () {},
            onClosePeek: () {},
            onCursorChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hover'), findsWidgets);
    expect(find.textContaining('Login With Credentials'), findsWidgets);
    expect(find.textContaining('checkout.robot:8'), findsOneWidget);
    // Editor action strip moved to the window menu bar.
    expect(find.byKey(const Key('editor.find')), findsNothing);
    expect(find.byKey(const Key('editor.save')), findsNothing);
    expect(find.byKey(const Key('editor.more')), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
  });
}

class _FakeTransportGateway implements TransportGateway {
  _FakeTransportGateway({
    this.withWorkspace = false,
    // Shell unit tests expect the welcome screen; production default is on.
    this.settings = const AppSettings(
      appearance: AppearanceSettings(restoreLastProject: false),
    ),
    this.openProjectByPathError,
  });

  final bool withWorkspace;
  final AppSettings settings;
  final Object? openProjectByPathError;
  String? activatedId;
  String? lastOpenedProjectPath;
  int openProjectByPathCalls = 0;

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
  Future<ProjectInfo> createProject({required String name}) async {
    return ProjectInfo(
      id: 'p-new',
      workspaceId: '1',
      name: name,
      path: '/tmp/$name',
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
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<OpenProjectByPathResult> openProjectByPath(
    String path, {
    bool force = false,
  }) async {
    openProjectByPathCalls++;
    lastOpenedProjectPath = path;
    final error = openProjectByPathError;
    if (error != null) {
      throw error;
    }
    return OpenProjectByPathResult(
      workspace: WorkspaceInfo(
        id: '1',
        name: 'Alpha',
        path: '/tmp/Alpha',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      project: ProjectInfo(
        id: 'p-path',
        workspaceId: '1',
        name: 'Opened',
        path: path,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  @override
  Future<OpenProjectByPathResult> createStandaloneProject({
    required String name,
    required String location,
  }) async {
    final path = '$location/$name';
    return OpenProjectByPathResult(
      workspace: WorkspaceInfo(
        id: '1',
        name: name,
        path: path,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      project: ProjectInfo(
        id: 'p-standalone',
        workspaceId: '1',
        name: name,
        path: path,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      needsEnvironment: true,
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
  Future<List<PythonInterpreterInfo>> listPythonInterpreters() async {
    return const [
      PythonInterpreterInfo(
        path: '/usr/bin/python3',
        version: '3.12.0',
        displayName: 'Python 3.12.0 — /usr/bin/python3',
      ),
    ];
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
    _environments = _environments
        .where((item) => item.id != environmentId)
        .toList();
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
  Future<PackageVersionList> listPackageVersions(String name) async {
    return PackageVersionList(
      name: name,
      latestVersion: '18.0.0',
      versions: const ['18.0.0', '17.0.0'],
    );
  }

  @override
  Future<PackageInfo> getPackage(String name) async {
    return _packages.firstWhere(
      (item) => item.name.toLowerCase() == name.toLowerCase(),
    );
  }

  @override
  Future<PackageOperationResult> installPackage(
    String name, {
    String? version,
    bool force = false,
  }) async {
    final package = PackageInfo(
      name: name,
      version: version ?? '1.0.0',
      latestVersion: version ?? '1.0.0',
      summary: 'Installed $name',
    );
    _packages = [
      for (final item in _packages)
        if (item.name.toLowerCase() != name.toLowerCase()) item,
      package,
    ];
    return PackageOperationResult(
      package: package,
      logs: [
        if (force) 'Force reinstalling $name',
        'Installing $name${version == null ? '' : '==$version'}',
        'Successfully installed $name',
      ],
      robotFrameworkInstalled:
          name.toLowerCase() == 'robotframework' ||
          _packages.any((item) => item.name.toLowerCase() == 'robotframework'),
      robotFrameworkVersion: '7.0',
    );
  }

  @override
  Future<PackageOperationResult> installRequirements(String filePath) async {
    return const PackageOperationResult(
      package: null,
      logs: ['Successfully installed requirements'],
      robotFrameworkInstalled: false,
    );
  }

  @override
  Future<PackageOperationResult> exportRequirements(String filePath) async {
    return PackageOperationResult(
      package: null,
      logs: ['Wrote packages to $filePath'],
      robotFrameworkInstalled: true,
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

  String? lastRunConfigurationId;
  final List<RunConfigurationInfo> _runConfigurations = [];
  String? _activeRunConfigurationId;

  @override
  Future<ExecutionInfo> runFile({String? file, String? configurationId}) async {
    lastRunConfigurationId = configurationId;
    return ExecutionInfo(
      id: 'run-file',
      workspaceId: '1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: file ?? 'tests',
      status: ExecutionStatus.idle,
      startedAt: DateTime.utc(2026, 1, 1),
      configurationId: configurationId,
      configurationName: _configName(configurationId),
    );
  }

  @override
  Future<ExecutionInfo> runProject({
    bool confirm = false,
    String? configurationId,
  }) async {
    lastRunConfigurationId = configurationId;
    return ExecutionInfo(
      id: 'run-project',
      workspaceId: '1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Demo',
      suite: 'project',
      status: ExecutionStatus.idle,
      startedAt: DateTime.utc(2026, 1, 1),
      configurationId: configurationId,
      configurationName: _configName(configurationId),
    );
  }

  String _configName(String? id) {
    if (id == null) return '';
    for (final item in _runConfigurations) {
      if (item.id == id) return item.name;
    }
    return '';
  }

  @override
  Future<TestNodeInfo> getTestTree({String? query, bool lazy = true}) async {
    return const TestNodeInfo(
      id: 'workspace:1',
      kind: 'workspace',
      name: 'Alpha',
      children: [
        TestNodeInfo(
          id: 'project:p1',
          kind: 'project',
          name: 'Demo',
          children: [
            TestNodeInfo(
              id: 'suite:s1',
              kind: 'suite',
              name: 'demo',
              path: '/tmp/demo.robot',
              children: [
                TestNodeInfo(
                  id: 'test:t1',
                  kind: 'test',
                  name: 'Login',
                  path: '/tmp/demo.robot',
                  line: 3,
                  status: TestNodeStatus.pass,
                  tags: ['smoke'],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<int> countTests({String? tag, bool projectWide = false}) async => 1;

  @override
  Future<List<TestNodeInfo>> getTestsForFile(String path) async => const [];

  @override
  Future<ExecutionInfo> runTest({
    required String file,
    required String name,
    String? configurationId,
  }) => runFile(file: file, configurationId: configurationId);

  @override
  Future<ExecutionInfo> runTestSuite({
    String? file,
    bool confirm = false,
    String? configurationId,
  }) => runProject(configurationId: configurationId);

  @override
  Future<ExecutionInfo> runTestsByTag(
    String tag, {
    bool confirm = false,
    String? configurationId,
  }) => runProject(configurationId: configurationId);

  @override
  Future<ExecutionInfo> runFailedTests({String? configurationId}) =>
      runProject(configurationId: configurationId);

  @override
  Future<ExecutionInfo> runSelectedTests(
    List<({String file, String name})> tests, {
    String? configurationId,
  }) => runProject(configurationId: configurationId);

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

  static final _sampleRun = ExecutionInfo(
    id: 'run-1',
    workspaceId: '1',
    projectId: 'p1',
    environmentId: 'e1',
    projectName: 'Demo',
    suite: 'tests/demo.robot',
    status: ExecutionStatus.finished,
    startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
    durationMs: 1200,
    exitCode: 0,
  );

  @override
  Future<List<ExecutionInfo>> listReports() async {
    if (!withWorkspace) return [];
    return [_sampleRun];
  }

  @override
  Future<ExecutionInfo> getReport(String runId) async => _sampleRun;

  @override
  Future<void> deleteReport(String runId) async {}

  @override
  Future<String> openReportLog(String runId) async => '/tmp/log.html';

  @override
  Future<String> openReportHtml(String runId) async => '/tmp/report.html';

  @override
  Future<String> openReportXml(String runId) async => '/tmp/output.xml';

  @override
  Future<String> revealReport(String runId) async => '/tmp/Reports';

  @override
  Future<DashboardSummary> getReportsDashboard() async {
    if (!withWorkspace) {
      return const DashboardSummary(totalRuns: 0);
    }
    return DashboardSummary(
      totalRuns: 1,
      passRate: 100,
      averageDurationMs: 1200,
      lastRun: _sampleRun,
      recentRuns: [_sampleRun],
      recentFailures: const [],
    );
  }

  static const _sampleSymbol = IndexedSymbolInfo(
    id: 'sym-login',
    name: 'Login With Credentials',
    kind: SymbolKind.keyword,
    filePath: 'resources/login.resource',
    line: 12,
    documentation: 'Logs into the application.',
  );

  static const _indexStatus = IndexStatusInfo(
    state: 'ready',
    filesIndexed: 8,
    keywordsIndexed: 24,
    librariesIndexed: 2,
    variablesIndexed: 11,
    lastIndexedAt: null,
  );

  @override
  Future<IndexStatusInfo> rebuildIndex() async => _indexStatus;

  @override
  Future<IndexStatusInfo> getIndexStatus() async {
    if (!withWorkspace) {
      return const IndexStatusInfo(state: 'idle');
    }
    return _indexStatus;
  }

  @override
  Future<InsightsInfo> getInsights() async {
    return const InsightsInfo();
  }

  @override
  Future<List<IndexedSymbolInfo>> searchSymbols({
    String query = '',
    SymbolKind? kind,
    int limit = 100,
  }) async {
    if (query.isEmpty) return const [];
    if (kind != null && kind != SymbolKind.keyword) return const [];
    return const [_sampleSymbol];
  }

  @override
  Future<ContentSearchResultInfo> searchContent({
    String query = '',
    int limit = 500,
    int contextLines = 1,
  }) async {
    if (query.isEmpty) {
      return const ContentSearchResultInfo(
        query: '',
        truncated: false,
        filesScanned: 0,
        files: [],
      );
    }
    return ContentSearchResultInfo(
      query: query,
      truncated: false,
      filesScanned: 1,
      files: [
        ContentFileHitsInfo(
          path: 'tests/login.robot',
          matchCount: 1,
          matches: [
            ContentMatchInfo(
              line: 8,
              column: 1,
              text: '    Login With Credentials    \${USER}    \${PASS}',
              enclosing: const EnclosingSymbolInfo(
                kind: 'test_case',
                name: 'Valid Login',
                line: 5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<RunFailuresInfo> getRunFailures(String runId) async {
    return RunFailuresInfo(
      runId: runId,
      items: const [
        RunTestFailureInfo(
          runId: 'run-1',
          name: 'Valid Login',
          message: 'Login failed',
          source: 'tests/login.robot',
          line: 5,
        ),
      ],
    );
  }

  @override
  Future<IndexedSymbolInfo?> languageDefinition({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    return _sampleSymbol;
  }

  @override
  Future<List<SymbolReferenceInfo>> languageReferences({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    return [
      SymbolReferenceInfo(
        name: 'Login With Credentials',
        filePath: 'tests/login.robot',
        line: 8,
        context: r'Login With Credentials    ${USER}    ${PASS}',
      ),
    ];
  }

  @override
  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) async {
    return const HoverInfo(
      name: 'Login With Credentials',
      kind: SymbolKind.keyword,
      filePath: 'resources/login.resource',
      line: 12,
      documentation: 'Logs into the application.',
    );
  }

  @override
  Future<List<IndexedSymbolInfo>> documentSymbols(String filePath) async {
    return const [
      IndexedSymbolInfo(
        id: 'doc-1',
        name: 'Login',
        kind: SymbolKind.testCase,
        filePath: 'tests/login.robot',
        line: 3,
      ),
    ];
  }

  @override
  Future<DocumentAnalysisInfo> analyzeDocument({
    required String filePath,
    required String content,
  }) async {
    return DocumentAnalysisInfo(
      filePath: filePath,
      root: DocumentSymbolNode(
        id: 'suite:1:Login',
        name: 'login',
        kind: SymbolKind.testSuite,
        line: 1,
        endLine: 10,
        children: const [
          DocumentSymbolNode(
            id: 'section:1:Tests',
            name: 'Tests',
            kind: SymbolKind.section,
            line: 1,
            endLine: 10,
            children: [
              DocumentSymbolNode(
                id: 'test_case:3:Login',
                name: 'Login',
                kind: SymbolKind.testCase,
                line: 3,
                endLine: 8,
              ),
            ],
          ),
        ],
      ),
      foldingRanges: const [FoldingRangeInfo(startLine: 2, endLine: 7)],
    );
  }

  @override
  Future<AppSettings> getSettings() async => settings;

  @override
  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async =>
      settings;

  @override
  Future<AppSettings> resetSettings() async => const AppSettings();

  @override
  Future<List<IndexedSymbolInfo>> workspaceSymbols({
    String query = '',
    int limit = 200,
  }) async {
    if (query.isEmpty) return const [];
    return const [_sampleSymbol];
  }

  @override
  Future<List<CompletionItemInfo>> languageCompletion({
    required String filePath,
    required int line,
    required int column,
    required String content,
    String query = '',
  }) async {
    return const [CompletionItemInfo(label: 'Log', kind: 'keyword')];
  }

  @override
  Future<void> languageCompletionUsage({
    required String label,
    String kind = '',
  }) async {}

  @override
  Future<List<DiagnosticInfo>> languageDiagnostics({
    required String filePath,
    required String content,
  }) async {
    return const [];
  }

  @override
  Future<String> languageFormat({
    required String filePath,
    required String content,
    int? startLine,
    int? endLine,
  }) async {
    return content.trimRight();
  }

  @override
  Future<RenameResultInfo> languageRename({
    required String filePath,
    required int line,
    required int column,
    required String content,
    required String newName,
  }) async {
    return const RenameResultInfo();
  }

  @override
  Future<SignatureHelpInfo?> languageSignatureHelp({
    required String filePath,
    required int line,
    required int column,
    required String content,
    bool hover = false,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryInfo>> languageLibraries() async => const [];

  @override
  Future<LibraryInfo?> languageLibrary(String name) async => null;

  @override
  Future<List<PluginInfo>> listPlugins() async {
    return const [
      PluginInfo(
        id: 'pip-installer',
        name: 'Pip Installer',
        version: '1.0.0',
        status: 'enabled',
        enabled: true,
        isBuiltin: true,
        capabilities: ['installer'],
      ),
    ];
  }

  @override
  Future<List<PluginInfo>> refreshPlugins() => listPlugins();

  @override
  Future<PluginInfo?> getPlugin(String id) async {
    final plugins = await listPlugins();
    return plugins.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<PluginInfo> enablePlugin(String id) async {
    return (await getPlugin(id))!;
  }

  @override
  Future<PluginInfo> disablePlugin(String id) async {
    return (await getPlugin(id))!;
  }

  @override
  Future<PluginInfo> reloadPlugin(String id) async {
    return (await getPlugin(id))!;
  }

  @override
  Future<GitStatusInfo> getGitStatus() async {
    if (!withWorkspace) {
      return const GitStatusInfo(
        repository: GitRepositoryInfo(isRepository: false),
      );
    }
    return const GitStatusInfo(
      repository: GitRepositoryInfo(
        isRepository: true,
        root: '/tmp/WS',
        branch: 'main',
        head: 'abc1234567890',
        clean: false,
      ),
      changes: [
        GitFileChangeInfo(
          path: 'tests/login.robot',
          status: GitFileStatus.modified,
        ),
        GitFileChangeInfo(path: 'README.md', status: GitFileStatus.untracked),
      ],
    );
  }

  @override
  Future<GitRepositoryInfo> initGitRepository() async {
    return const GitRepositoryInfo(
      isRepository: true,
      root: '/tmp/WS',
      branch: 'main',
    );
  }

  @override
  Future<GitRepositoryInfo?> refreshGitRepository() async {
    return (await getGitStatus()).repository;
  }

  @override
  Future<List<GitCommitInfo>> getGitHistory({int limit = 50}) async {
    if (!withWorkspace) return const [];
    return [
      GitCommitInfo(
        hash: 'abc1234567890',
        shortHash: 'abc1234',
        author: 'Dev',
        email: 'dev@example.com',
        date: DateTime.utc(2026, 1, 1),
        message: 'Initial commit',
      ),
    ];
  }

  @override
  Future<GitCommitDetailInfo> getGitCommitDetail(String commitHash) async {
    return GitCommitDetailInfo(
      hash: commitHash,
      shortHash: commitHash.substring(0, 7),
      author: 'Dev',
      email: 'dev@example.com',
      date: DateTime.utc(2026, 1, 1),
      message: 'Initial commit',
      files: const [
        GitFileChangeInfo(
          path: 'tests/login.robot',
          status: GitFileStatus.added,
        ),
      ],
    );
  }

  @override
  Future<List<GitBranchInfo>> getGitBranches() async {
    if (!withWorkspace) return const [];
    return const [
      GitBranchInfo(name: 'main', current: true),
      GitBranchInfo(name: 'feature/login'),
    ];
  }

  @override
  Future<GitRepositoryInfo> checkoutGitBranch(String branch) async {
    return GitRepositoryInfo(
      isRepository: true,
      root: '/tmp/WS',
      branch: branch,
      head: 'abc1234567890',
    );
  }

  @override
  Future<GitBranchInfo> createGitBranch(
    String name, {
    String? startPoint,
  }) async {
    return GitBranchInfo(name: name);
  }

  @override
  Future<void> deleteGitBranch(String name) async {}

  @override
  Future<GitCommitInfo> commitGitChanges({
    required String message,
    List<String>? files,
  }) async {
    return GitCommitInfo(
      hash: 'def1234567890',
      shortHash: 'def1234',
      author: 'Dev',
      email: 'dev@example.com',
      date: DateTime.utc(2026, 1, 2),
      message: message,
    );
  }

  @override
  Future<GitRemoteResultInfo> fetchGit() async {
    return const GitRemoteResultInfo(success: true, message: 'Fetch completed');
  }

  @override
  Future<GitRemoteResultInfo> pullGit() async {
    return const GitRemoteResultInfo(success: true, message: 'Pull completed');
  }

  @override
  Future<GitRemoteResultInfo> pushGit() async {
    return const GitRemoteResultInfo(success: true, message: 'Push completed');
  }

  @override
  Future<List<GitRemoteInfo>> listGitRemotes() async => const [];

  @override
  Future<List<GitRemoteInfo>> addGitRemote({
    String name = 'origin',
    required String url,
  }) async => [GitRemoteInfo(name: name, url: url)];

  @override
  Future<GitIdentityInfo> getGitIdentity() async => const GitIdentityInfo();

  @override
  Future<GitIdentityInfo> setGitIdentity({
    required String name,
    required String email,
    String scope = 'local',
  }) async => GitIdentityInfo(
    name: name,
    email: email,
    source: scope,
    isComplete: true,
  );

  @override
  Future<GitDiffInfo> getGitDiff({String? filePath, String? commit}) async {
    return GitDiffInfo(
      filePath: filePath,
      lines: const [
        GitDiffLineInfo(kind: 'removed', left: 'old line', leftLine: 1),
        GitDiffLineInfo(kind: 'added', right: 'new line', rightLine: 1),
      ],
    );
  }

  @override
  Future<DoctorProfilesBundle> getDoctorProfiles() async {
    return const DoctorProfilesBundle(
      profiles: [
        DoctorProfileInfo(
          id: 'default',
          title: 'Structural',
          description:
              'Circular imports, duplicate keywords, and potentially unused assets.',
          providerIds: [
            'circular_dependency',
            'duplicate_keyword',
            'unused_keyword',
            'unused_resource',
          ],
        ),
      ],
    );
  }

  @override
  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  }) async {
    return DoctorReport(
      id: 'report-1',
      projectId: projectId ?? 'proj',
      profile: profile,
      createdAt: DateTime.utc(2026, 8, 3),
      graphVersion: 'gv1',
      summary: const DoctorHealthSummary(
        totalFindings: 2,
        bySeverity: {'error': 1, 'warning': 1},
        byCategory: {'dependencies': 1, 'maintainability': 1},
        criticalIssues: 1,
      ),
      findings: const [
        DoctorFinding(
          id: 'f1',
          inspectionId: 'missing_import',
          severity: 'error',
          message: "Unresolved import '../resources/missing.resource'",
          confidence: 'low',
          category: 'dependencies',
          rationale: 'A Resource import path could not be resolved on disk.',
          supportsFix: true,
          fixId: 'fix_missing_import',
          estimatedRisk: 'medium',
          filePath: 'tests/login.robot',
          line: 3,
        ),
        DoctorFinding(
          id: 'f2',
          inspectionId: 'unused_keyword',
          severity: 'warning',
          message: "Keyword 'Dead Keyword' is never called",
          confidence: 'high',
          category: 'maintainability',
          rationale: 'No bound callers exist in the semantic call graph.',
          supportsFix: true,
          fixId: 'remove_unused_keyword',
          estimatedRisk: 'medium',
          filePath: 'resources/common.resource',
          line: 5,
        ),
      ],
      grouped: const [
        DoctorCategoryGroup(
          category: 'dependencies',
          findings: [
            DoctorFinding(
              id: 'f1',
              inspectionId: 'missing_import',
              severity: 'error',
              message: "Unresolved import '../resources/missing.resource'",
              confidence: 'low',
              category: 'dependencies',
              rationale:
                  'A Resource import path could not be resolved on disk.',
              supportsFix: true,
              fixId: 'fix_missing_import',
              filePath: 'tests/login.robot',
              line: 3,
            ),
          ],
        ),
        DoctorCategoryGroup(
          category: 'maintainability',
          findings: [
            DoctorFinding(
              id: 'f2',
              inspectionId: 'unused_keyword',
              severity: 'warning',
              message: "Keyword 'Dead Keyword' is never called",
              confidence: 'high',
              category: 'maintainability',
              rationale: 'No bound callers exist in the semantic call graph.',
              supportsFix: true,
              filePath: 'resources/common.resource',
              line: 5,
            ),
          ],
        ),
      ],
      topRecommendations: const [
        DoctorRecommendation(
          rank: 1,
          findingId: 'f1',
          reason:
              'Critical correctness / dependency issue — fix before shipping.',
          finding: DoctorFinding(
            id: 'f1',
            inspectionId: 'missing_import',
            severity: 'error',
            message: "Unresolved import '../resources/missing.resource'",
            confidence: 'low',
            category: 'dependencies',
            rationale: 'A Resource import path could not be resolved on disk.',
            supportsFix: true,
            filePath: 'tests/login.robot',
            line: 3,
          ),
        ),
      ],
      executionSnapshot: const DoctorExecutionSnapshot(
        projectId: 'proj',
        linkedRuns: 0,
      ),
    );
  }

  @override
  Future<DoctorReport> getDoctorReport(String reportId) async {
    final report = await runDoctor();
    return DoctorReport(
      id: reportId,
      projectId: report.projectId,
      profile: report.profile,
      createdAt: report.createdAt,
      graphVersion: report.graphVersion,
      summary: report.summary,
      findings: report.findings,
      grouped: report.grouped,
      topRecommendations: report.topRecommendations,
      executionSnapshot: report.executionSnapshot,
    );
  }

  @override
  Future<List<DoctorReportSummary>> getDoctorHistory({
    String? projectId,
    int limit = 20,
  }) async {
    return [
      DoctorReportSummary(
        id: 'report-1',
        projectId: projectId ?? 'proj',
        profile: 'default',
        createdAt: DateTime.utc(2026, 8, 3),
        totalFindings: 2,
        criticalIssues: 1,
      ),
    ];
  }

  @override
  Future<RunConfigurationListInfo> listRunConfigurations() async {
    return RunConfigurationListInfo(
      activeId: _activeRunConfigurationId,
      configurations: List.unmodifiable(_runConfigurations),
    );
  }

  @override
  Future<RunConfigurationInfo> createRunConfiguration(
    RunConfigurationDraft draft,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    final item = RunConfigurationInfo(
      id: 'cfg-${_runConfigurations.length + 1}',
      name: draft.name,
      environmentId: draft.environmentId,
      includeTags: draft.includeTags,
      excludeTags: draft.excludeTags,
      variables: draft.variables,
      variableFiles: draft.variableFiles,
      extraRobotArgs: draft.extraRobotArgs,
      createdAt: now,
      updatedAt: now,
    );
    _runConfigurations.add(item);
    _activeRunConfigurationId = item.id;
    return item;
  }

  @override
  Future<RunConfigurationInfo> updateRunConfiguration(
    String configurationId,
    RunConfigurationDraft draft,
  ) async {
    final index = _runConfigurations.indexWhere(
      (item) => item.id == configurationId,
    );
    final now = DateTime.utc(2026, 1, 2);
    final updated = RunConfigurationInfo(
      id: configurationId,
      name: draft.name,
      environmentId: draft.environmentId,
      includeTags: draft.includeTags,
      excludeTags: draft.excludeTags,
      variables: draft.variables,
      variableFiles: draft.variableFiles,
      extraRobotArgs: draft.extraRobotArgs,
      createdAt: index >= 0 ? _runConfigurations[index].createdAt : now,
      updatedAt: now,
    );
    if (index >= 0) {
      _runConfigurations[index] = updated;
    } else {
      _runConfigurations.add(updated);
    }
    return updated;
  }

  @override
  Future<void> deleteRunConfiguration(String configurationId) async {
    _runConfigurations.removeWhere((item) => item.id == configurationId);
    if (_activeRunConfigurationId == configurationId) {
      _activeRunConfigurationId = null;
    }
  }

  @override
  Future<RunConfigurationInfo> duplicateRunConfiguration(
    String configurationId,
  ) async {
    final source = _runConfigurations.firstWhere(
      (item) => item.id == configurationId,
    );
    final now = DateTime.utc(2026, 1, 3);
    final copy = RunConfigurationInfo(
      id: 'cfg-copy-${_runConfigurations.length + 1}',
      name: '${source.name} copy',
      environmentId: source.environmentId,
      includeTags: source.includeTags,
      excludeTags: source.excludeTags,
      variables: source.variables,
      variableFiles: source.variableFiles,
      extraRobotArgs: source.extraRobotArgs,
      createdAt: now,
      updatedAt: now,
    );
    _runConfigurations.add(copy);
    return copy;
  }

  @override
  Future<String?> activateRunConfiguration(String? configurationId) async {
    _activeRunConfigurationId = configurationId;
    return _activeRunConfigurationId;
  }

  @override
  Future<FileContentInfo> readFile(String path) async {
    return FileContentInfo(
      path: path,
      content: '*** Test Cases ***\nSample Test',
      mtime: 100,
    );
  }

  @override
  Future<FileWriteResult> writeFile({
    required String path,
    required String content,
  }) async {
    return FileWriteResult(path: path, mtime: 101);
  }

  @override
  Future<FileMutationResult> createFile({
    required String path,
    String content = '',
  }) async {
    return FileMutationResult(path: path);
  }

  @override
  Future<FileMutationResult> createDirectory({required String path}) async {
    return FileMutationResult(path: path, isDir: true);
  }

  @override
  Future<FileMutationResult> renamePath({
    required String path,
    required String newName,
  }) async {
    return FileMutationResult(path: path, oldPath: path, name: newName);
  }

  @override
  Future<FileMutationResult> movePath({
    required String path,
    required String destinationDir,
  }) async {
    return FileMutationResult(path: '$destinationDir/${path.split('/').last}');
  }

  @override
  Future<FileMutationResult> duplicatePath({required String path}) async {
    return FileMutationResult(path: '$path copy');
  }

  @override
  Future<FileMutationResult> deletePath({required String path}) async {
    return FileMutationResult(path: path, deleted: true);
  }

  @override
  Future<List<FileTreeNode>> listFileTree({String? path, int depth = 3}) async {
    if (!withWorkspace) return const [];
    return const [
      FileTreeNode(
        name: 'tests',
        path: '/tmp/WS/tests',
        relativePath: 'tests',
        isDir: true,
        children: [
          FileTreeNode(
            name: 'login.robot',
            path: '/tmp/WS/tests/login.robot',
            relativePath: 'tests/login.robot',
            isDir: false,
            suffix: '.robot',
          ),
        ],
      ),
    ];
  }
}
