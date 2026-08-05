import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/reports/run_details_panel.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/toolbar/app_toolbar.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';

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
