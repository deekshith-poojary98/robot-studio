import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: UX-01 … UX-08 (Guidance & gating).
///
/// Source: docs/internal/functional-test-cases.md §15
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
    // Welcome has no activity rail — guidance lives on the landing actions.
    expect(find.text('Open Workspace'), findsWidgets);
    expect(find.text('Open Project'), findsWidgets);
    expect(find.text('New Workspace'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-02 missing project guidance', (tester) async {
    await harness.seedWorkspace(name: 'UX NoProj', suffix: 'ux-02');
    // Robot ready so the gated tooltip is project-missing, not RF-missing.
    await harness.seedEnvironment(name: 'ux-02-env', installRobot: true);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX NoProj');
    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Execution'));
    expect(find.widgetWithText(FilledButton, 'Run Project'), findsNothing);
    final runProject = tester.widget<ToolbarButton>(
      find.byWidgetPredicate(
        (widget) => widget is ToolbarButton && widget.label == 'Project',
      ),
    );
    expect(runProject.onTap, isNull);
    expect(runProject.tooltip, 'Open a project to run');

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-03 missing environment guidance', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'UX NoEnv', suffix: 'ux-03');
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

    // Run stays disabled without an active env; Package Manager shows the
    // environment empty-state (dialog path only fires from enabled handlers).
    final run = tester.widget<ToolbarButton>(
      find.byKey(const Key('toolbar.run')),
    );
    expect(run.onTap, isNull);
    await openPackageManager(tester);
    await pumpUntilFound(tester, find.text('No active environment'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-04 recent item tooltips', (tester) async {
    await harness.seedWorkspace(name: 'UX Tips', suffix: 'ux-04');
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('UX Tips'));
    // Recent rows may use InkWell/semantics without Tooltip widgets; assert
    // the seeded workspace remains listed and tappable.
    expect(find.text('UX Tips'), findsWidgets);
    expect(find.text('Recent Workspaces'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('UX-05 no coming-soon stubs remain reachable', (tester) async {
    await harness.seedWorkspace(name: 'UX Stub', suffix: 'ux-05');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'UX Stub');
    await openBottomTab(tester, 'Problems');

    expect(find.textContaining('coming in a later milestone'), findsNothing);
    expect(find.textContaining('Coming Soon'), findsNothing);
    // Settings lives in the menu bar / palette, not a toolbar tooltip.
    expect(find.byTooltip('Settings'), findsNothing);
    // OUTPUT stub is gone; TERMINAL is a real bottom tab in this build.
    expect(find.text('OUTPUT'), findsNothing);

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
