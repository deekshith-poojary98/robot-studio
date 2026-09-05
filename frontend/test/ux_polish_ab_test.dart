import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/gateway/models/project_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/reports/run_details_panel.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/toolbar/app_toolbar.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';
import 'package:robot_studio/presentation/workspace/explorer_file_actions.dart';

void main() {
  testWidgets('status bar omits backend connection chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(robotVersion: '7.0', pythonVersion: '3.12.8'),
        ),
      ),
    );
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('READY'), findsNothing);
    expect(find.text('ROBOT 7.0'), findsOneWidget);
    expect(find.text('PYTHON 3.12.8'), findsOneWidget);
    expect(find.textContaining('ENV '), findsNothing);
  });

  testWidgets('empty environment chip offers Create and Manage', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var createTapped = false;
    var manageTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'demo',
            environmentLabel: 'No environment',
            backendConnected: true,
            environmentNames: const [],
            onCreateEnvironment: () => createTapped = true,
            onManageEnvironments: () => manageTapped = true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toolbar.environment')));
    await tester.pumpAndSettle();

    expect(find.text('Create Environment…'), findsOneWidget);
    expect(find.text('Manage Environments…'), findsOneWidget);

    await tester.tap(find.text('Create Environment…'));
    await tester.pumpAndSettle();
    expect(createTapped, isTrue);
    expect(manageTapped, isFalse);
  });

  testWidgets('project chip reveals in the OS file manager', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var revealed = false;
    var opened = false;
    final project = ProjectInfo(
      id: 'p1',
      workspaceId: 'w1',
      name: 'OrangeHRM',
      path: '/tmp/OrangeHRM',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'OrangeHRM',
            environmentLabel: 'default',
            backendConnected: true,
            recentProjects: [project],
            selectedProjectId: project.id,
            onOpenProject: () => opened = true,
            onRevealProject: () => revealed = true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toolbar.project')));
    await tester.pumpAndSettle();

    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('New Project'), findsNothing);
    expect(find.text(ExplorerFileActions.revealLabel()), findsOneWidget);

    await tester.tap(find.text(ExplorerFileActions.revealLabel()));
    await tester.pumpAndSettle();
    expect(revealed, isTrue);
    expect(opened, isFalse);
  });

  testWidgets('project chip Open Project runs after the menu closes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = false;
    final project = ProjectInfo(
      id: 'p1',
      workspaceId: 'w1',
      name: 'OrangeHRM',
      path: '/tmp/OrangeHRM',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'OrangeHRM',
            environmentLabel: 'default',
            backendConnected: true,
            recentProjects: [project],
            selectedProjectId: project.id,
            onOpenProject: () => opened = true,
            onNewProject: () {},
            onRevealProject: () {},
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toolbar.project')));
    await tester.pumpAndSettle();

    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);

    await tester.tap(find.text('Open Project'));
    await tester.pump();
    expect(opened, isFalse);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('project, environment and branch chips share one height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'OrangeHRM',
            environmentLabel: 'No environment',
            backendConnected: true,
            environmentNames: const ['default'],
            selectedEnvironmentName: 'default',
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The chips wrap different content, so measure the rendered boxes rather
    // than trusting that padding happens to add up.
    double chipHeight(String label) {
      final box = find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first;
      return tester.getSize(box).height;
    }

    final project = chipHeight('OrangeHRM');
    final environment = chipHeight('default');
    final branch = chipHeight('No branch');

    expect(environment, project);
    expect(branch, project);
    expect(project, AppControlHeight.toolbarChip);
  });

  testWidgets('idle toolbar hides Idle badge and mutes Stop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            backendConnected: true,
            isExecutionRunning: false,
            executionStatusLabel: 'Idle',
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('Idle'), findsNothing);
    expect(find.textContaining('Last:'), findsNothing);
    final stop = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.stop')),
    );
    expect(stop.onTap, isNull);
    expect(stop.danger, isFalse);
    expect(stop.primary, isFalse);

    // Only Run stays visually primary; the others are quiet segments.
    final run = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.run')),
    );
    expect(run.primary, isTrue);
    final runProject = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.run-project')),
    );
    expect(runProject.primary, isFalse);
  });

  testWidgets('run controls are one attached bar of equal segments', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            backendConnected: true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    Rect rectOf(String key) =>
        tester.getRect(find.byKey(Key(key)).hitTestable().first);

    final run = rectOf('toolbar.run');
    final project = rectOf('toolbar.run-project');
    final stop = rectOf('toolbar.stop');

    // Same width and height across all three.
    expect(project.width, run.width);
    expect(stop.width, run.width);
    expect(project.height, run.height);
    expect(stop.height, run.height);

    // Attached: only the 1px hairline separator sits between segments.
    expect(project.left - run.right, closeTo(1, 0.01));
    expect(stop.left - project.right, closeTo(1, 0.01));

    // One rounded rectangle around the lot, at the shared control height.
    expect(find.byType(ToolbarButtonGroup), findsOneWidget);
    expect(
      tester.getSize(find.byType(ToolbarButtonGroup)).height,
      AppControlHeight.toolbarAction,
    );
  });

  testWidgets('Stop stays fully visible at minimum window width', (
    tester,
  ) async {
    // Matches desktop min size (1360×800).
    await tester.binding.setSurfaceSize(const Size(1360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'my-robot-test-project',
            environmentLabel: 'venv',
            backendConnected: true,
            environmentNames: const ['venv'],
            selectedEnvironmentName: 'venv',
            gitBranchLabel: 'main',
            gitBranches: const ['main'],
            showGitRemoteActions: true,
            executionStatusLabel: 'Finished',
            isExecutionRunning: false,
            runConfigurationsEnabled: true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stop = tester.getRect(find.byKey(const Key('toolbar.stop')));
    expect(stop.right, lessThanOrEqualTo(1360));
    expect(stop.left, greaterThan(0));
    expect(find.byKey(const Key('toolbar.stop')).hitTestable(), findsOneWidget);
  });

  testWidgets('search is centered and run cluster sits on the right', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'Default',
            backendConnected: true,
            environmentNames: const ['Default'],
            selectedEnvironmentName: 'Default',
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final search = tester.getRect(find.byKey(const Key('toolbar.search')));
    final stop = tester.getRect(find.byKey(const Key('toolbar.stop')));
    final env = tester.getRect(find.byKey(const Key('toolbar.environment')));
    final project = tester.getRect(find.byKey(const Key('toolbar.project')));

    // Search roughly window-centered.
    final searchCenter = (search.left + search.right) / 2;
    expect(searchCenter, closeTo(800, 160));

    // Project + env on the left; run cluster flush to the trailing side.
    expect(project.left, lessThan(search.left));
    expect(env.left, lessThan(search.left));
    expect(stop.right, greaterThan(1500));
    expect(stop.right, lessThanOrEqualTo(1600));
    expect(stop.left, greaterThan(search.right));
  });

  testWidgets('failed status shows Last: prefix', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            backendConnected: true,
            isExecutionRunning: false,
            executionStatusLabel: 'Failed',
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('Last: Failed'), findsOneWidget);
  });

  testWidgets('empty suite shows Last: No tests, not Failed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'WS',
            environmentLabel: 'robot-main',
            backendConnected: true,
            isExecutionRunning: false,
            executionStatusLabel: 'No tests',
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('Last: No tests'), findsOneWidget);
    expect(find.text('Last: Failed'), findsNothing);
  });

  testWidgets('sidebar panels expose descriptive tooltips', (tester) async {
    expect(SidebarPanel.reports.tooltip, contains('HTML reports'));
    expect(SidebarPanel.explorer.tooltip, contains('projects'));
  });

  testWidgets('run details artifact hyperlinks open report', (tester) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(900, 900));
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
              status: ExecutionStatus.finished,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              reportHtml: '/tmp/report.html',
              logHtml: '/tmp/log.html',
              outputXml: '/tmp/output.xml',
            ),
            onOpenReport: () => opened = true,
            onOpenLog: () {},
            onOpenXml: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open Report'), findsNothing);
    expect(find.text('report.html'), findsOneWidget);
    await tester.tap(find.text('report.html'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
