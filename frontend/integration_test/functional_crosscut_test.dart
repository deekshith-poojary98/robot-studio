import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: XR-01 … XR-06 (Cross-cutting / regression).
///
/// Source: docs/internal/functional-test-cases.md §16
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<void> ensureExecutionIdle() async {
    final status = await harness.api.executionStatus();
    final state = status['status']?.toString() ?? '';
    if (state == 'running' || state == 'starting' || state == 'stopping') {
      try {
        await harness.api.stopExecution();
      } catch (_) {}
      await waitForExecutionFinished(
        harness.api,
        timeout: const Duration(seconds: 90),
      );
    }
  }

  testWidgets('XR-01 full happy path smoke', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'XR Smoke', suffix: 'xr-01');
    await harness.seedEnvironment(name: 'xr-01-env', installRobot: true);
    final project = await harness.seedProject(name: 'XrSmoke');
    final path = '${project['path']}/tests/smoke.robot';
    await harness.api.writeFile(
      path: path,
      content: IntegrationFixtures.sampleRobot,
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'XR Smoke');
    await openProjectInExplorer(tester, projectName: 'XrSmoke');
    await openRobotFileInExplorer(
      tester,
      'smoke.robot',
      projectName: 'XrSmoke',
    );
    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);
    await openReports(tester);
    await pumpUntilFound(tester, find.textContaining('XrSmoke'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('XR-02 rapid panel switching stress', (tester) async {
    await harness.seedWorkspace(name: 'XR Panels', suffix: 'xr-02');
    await harness.seedEnvironment(name: 'xr-02-env', installRobot: false);
    await harness.seedProject(name: 'XrPanels');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XR Panels');

    const panels = [
      'Explorer',
      'Search',
      'Insights',
      'Tests',
      'Source Control',
      'Reports',
      'Packages',
      'Explorer',
    ];
    for (final panel in panels) {
      await tapSidebarPanel(tester, panel);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await pumpUntilFound(tester, find.textContaining('XrPanels'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('XR-03 window resize graceful', (tester) async {
    await harness.seedWorkspace(name: 'XR Resize', suffix: 'xr-03');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XR Resize');
    final view = tester.view;
    final original = view.physicalSize;
    addTearDown(() => view.resetPhysicalSize());

    view.physicalSize = const Size(900, 700);
    await tester.pump(const Duration(milliseconds: 200));
    view.physicalSize = const Size(1600, 1000);
    await tester.pump(const Duration(milliseconds: 200));
    view.physicalSize = original;
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    harness.expectNoFlutterErrors();
  });

  testWidgets('XR-04 short multi-run responsiveness', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'XR Loop', suffix: 'xr-04');
    await harness.seedEnvironment(name: 'xr-04-env', installRobot: true);
    final project = await harness.seedProject(name: 'XrLoop');
    final path = '${project['path']}/tests/loop.robot';
    await harness.api.writeFile(
      path: path,
      content: IntegrationFixtures.sampleRobot,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XR Loop');
    await openProjectInExplorer(tester, projectName: 'XrLoop');
    await openRobotFileInExplorer(tester, 'loop.robot', projectName: 'XrLoop');

    for (var i = 0; i < 3; i++) {
      await tapToolbarAction(tester, 'Run current file');
      await waitForExecutionFinished(harness.api);
    }
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'XR-05 backend restart mid-session',
    (tester) async {},
    skip: true,
  );

  testWidgets('XR-06 special characters in names', (tester) async {
    await harness.seedWorkspace(name: 'XR Spaced Name', suffix: 'xr-06');
    await harness.seedEnvironment(name: 'xr-06-env', installRobot: false);
    await harness.seedProject(name: 'Xr-Unicode-项目');
    await harness.launchAppWithWorkspace(
      tester,
      workspaceName: 'XR Spaced Name',
    );
    await pumpUntilFound(tester, find.textContaining('Xr-Unicode'));

    harness.expectNoFlutterErrors();
  });
}
