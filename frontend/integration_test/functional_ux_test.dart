import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: UX-01 … UX-08 (Guidance & gating).
///
/// Source: Robot Studio — Functional Test Cases.md §15
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<void> ensureExecutionIdle() async {
    final status = await harness.api.executionStatus();
    final state = status['status']?.toString() ?? '';
    if (state == 'running' ||
        state == 'starting' ||
        state == 'stopping') {
      try {
        await harness.api.stopExecution();
      } catch (_) {}
      await waitForExecutionFinished(
        harness.api,
        timeout: const Duration(seconds: 90),
      );
    }
  }

  testWidgets('UX-01 missing workspace guidance', (tester) async {
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('Recent Workspaces'));
    await openCommandPalette(tester);
    await tester.enterText(
      find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
      'New Project',
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Without workspace, New Project may be absent; Packages/Reports guidance
    // is exercised via toolbar/sidebar gated entry points.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    await tapSidebarPanel(tester, 'Packages');
    await pumpUntilFound(
      tester,
      find.textContaining('Workspace needed'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.textContaining('Open Workspace'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-02 missing project guidance', (tester) async {
    await harness.seedWorkspace(name: 'UX NoProj', suffix: 'ux-02');
    await harness.seedEnvironment(name: 'ux-02-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX NoProj');
    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Execution'));
    // Tests page is monitoring-only; launch is toolbar-gated without a project.
    expect(find.widgetWithText(FilledButton, 'Run Project'), findsNothing);
    final runProject = tester.widget<ToolbarButton>(
      find.byWidgetPredicate(
        (widget) => widget is ToolbarButton && widget.label == 'Run Project',
      ),
    );
    expect(runProject.onTap, isNull);
    expect(runProject.tooltip, 'Open a project to run');

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-03 missing environment guidance', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'UX NoEnv', suffix: 'ux-03');
    // Intentionally no environment — prior suite may leave another env active
    // on the shared backend, so clear activation by creating none and relying
    // on workspace open without an active environment pointer.
    final envs = await harness.api.listEnvironments();
    for (final env in envs) {
      final id = env['id'] as String?;
      if (id != null) {
        try {
          await harness.api.deleteEnvironment(id, deleteFiles: false);
        } catch (_) {}
      }
    }
    final project = await harness.seedProject(name: 'UxNoEnv');
    await harness.api.writeFile(
      path: '${project['path']}/tests/run.robot',
      content: IntegrationFixtures.sampleRobot,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX NoEnv');
    await openProjectInExplorer(tester, projectName: 'UxNoEnv');
    await openRobotFileInExplorer(
      tester,
      'run.robot',
      projectName: 'UxNoEnv',
    );
    await tapToolbarAction(tester, 'Run current file');
    await pumpUntilFound(
      tester,
      find.textContaining('Environment needed'),
      timeout: const Duration(seconds: 15),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-04 recent item tooltips', (tester) async {
    await harness.seedWorkspace(name: 'UX Tips', suffix: 'ux-04');
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('UX Tips'));
    expect(find.byType(Tooltip), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-05 no coming-soon stubs remain reachable', (tester) async {
    await harness.seedWorkspace(name: 'UX Stub', suffix: 'ux-05');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX Stub');
    await openBottomTab(tester, 'Problems');

    expect(find.textContaining('coming in a later milestone'), findsNothing);
    expect(find.textContaining('Coming Soon'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('OUTPUT'), findsNothing);
    expect(find.text('TERMINAL'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-06 AI entry points absent', (tester) async {
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('Recent Workspaces'));
    expect(find.textContaining('AI'), findsNothing);
    expect(find.textContaining('Assistant'), findsNothing);
    expect(find.textContaining('Copilot'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-07 failed badge clickable', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'UX FailBadge', suffix: 'ux-07');
    await harness.seedEnvironment(name: 'ux-07-env', installRobot: true);
    final project = await harness.seedProject(name: 'UxFail');
    final path = '${project['path']}/tests/fail.robot';
    await harness.api.writeFile(
      path: path,
      content: '*** Test Cases ***\nWill Fail\n    Fail    ux-07\n',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX FailBadge');
    await openProjectInExplorer(tester, projectName: 'UxFail');
    await openRobotFileInExplorer(
      tester,
      'fail.robot',
      projectName: 'UxFail',
    );
    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);
    await pumpUntilFound(tester, find.textContaining('Last: '));
    await tester.tap(find.textContaining('Last: ').first);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntilFound(
      tester,
      find.textContaining('ux-07'),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-08 welcome hierarchy', (tester) async {
    await harness.seedWorkspace(name: 'UX Welcome', suffix: 'ux-08');
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('Recent Workspaces'));
    expect(find.text('Recent Projects'), findsWidgets);
    expect(find.text('New Workspace'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
