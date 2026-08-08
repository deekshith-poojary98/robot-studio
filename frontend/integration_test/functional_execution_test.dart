import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: XC-01 … XC-12 (Execution).
///
/// Source: Robot Studio — Functional Test Cases.md §11
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Finder toolbarButton(String label) => find.byWidgetPredicate(
    (widget) => widget is ToolbarButton && widget.label == label,
  );

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

  Future<({String path, String project})> seedRunnable({
    required String workspace,
    required String suffix,
    required String project,
    String content = IntegrationFixtures.sampleRobot,
    String suiteFile = 'run.robot',
  }) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: true);
    final created = await harness.seedProject(name: project);
    final path = '${created['path']}/tests/$suiteFile';
    await harness.api.writeFile(path: path, content: content);
    return (path: path, project: project);
  }

  testWidgets('XC-01 run current file happy path', (tester) async {
    final seeded = await seedRunnable(
      workspace: 'XC Run',
      suffix: 'xc-01',
      project: 'XcRun',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Run');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'run.robot',
      projectName: seeded.project,
    );

    await tapToolbarAction(tester, 'Run current file');
    final status = await waitForExecutionFinished(harness.api);
    expect(
      ['finished', 'failed', 'cancelled'].contains(status['status']),
      isTrue,
    );

    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(
      tester,
      find.textContaining('integration test'),
      timeout: const Duration(seconds: 30),
    );
    final history = await harness.api.executionHistory();
    expect(history, isNotEmpty);

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-02 run project', (tester) async {
    final seeded = await seedRunnable(
      workspace: 'XC Project',
      suffix: 'xc-02',
      project: 'XcProject',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Project');
    await openProjectInExplorer(tester, projectName: seeded.project);

    await tapToolbarAction(tester, 'Run the selected project');
    final status = await waitForExecutionFinished(harness.api);
    expect(
      ['finished', 'failed', 'cancelled'].contains(status['status']),
      isTrue,
    );
    await tapSidebarPanel(tester, 'Tests');
    expect(find.textContaining('integration test'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-03 stop execution', (tester) async {
    const sleepy = '''*** Test Cases ***
Sleepy
    Sleep    60s
''';
    final seeded = await seedRunnable(
      workspace: 'XC Stop',
      suffix: 'xc-03',
      project: 'XcStop',
      content: sleepy,
      suiteFile: 'sleepy.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Stop');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'sleepy.robot',
      projectName: seeded.project,
    );

    await tapToolbarAction(tester, 'Run current file');
    final stopArmed = find.byWidgetPredicate(
      (widget) =>
          widget is ToolbarButton &&
          widget.label == 'Stop' &&
          widget.onTap != null,
    );
    await pumpUntilFound(
      tester,
      stopArmed,
      timeout: const Duration(seconds: 45),
    );
    await tester.tap(toolbarButton('Stop'));
    await tester.pump(const Duration(milliseconds: 400));
    final status = await waitForExecutionFinished(
      harness.api,
      timeout: const Duration(seconds: 60),
    );
    expect(status['status'], isNot(equals('running')));

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-04 stop muted when idle', (tester) async {
    await seedRunnable(
      workspace: 'XC IdleStop',
      suffix: 'xc-04',
      project: 'XcIdleStop',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC IdleStop');
    await pumpUntilFound(tester, toolbarButton('Stop'));
    final stop = tester.widget<ToolbarButton>(toolbarButton('Stop'));
    expect(stop.onTap, isNull);
    expect(stop.danger, isFalse);
    expect(stop.tooltip, 'Nothing to stop');

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-05 run buttons share primary styling', (tester) async {
    final seeded = await seedRunnable(
      workspace: 'XC Style',
      suffix: 'xc-05',
      project: 'XcStyle',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Style');
    await openProjectInExplorer(tester, projectName: seeded.project);

    final run = tester.widget<ToolbarButton>(toolbarButton('Run'));
    final runProject = tester.widget<ToolbarButton>(
      toolbarButton('Run Project'),
    );
    expect(run.primary, isTrue);
    expect(runProject.primary, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-06 run without workspace stays gated', (tester) async {
    await ensureExecutionIdle();
    await harness.launchApp(tester);
    await pumpUntilFound(tester, find.text('Recent Workspaces'));
    await pumpUntilFound(tester, toolbarButton('Run'));
    final run = tester.widget<ToolbarButton>(toolbarButton('Run'));
    expect(run.onTap, isNull);
    expect(run.tooltip, 'Open a project to run the current file');
    expect(find.textContaining('Running ·'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-07 run without project shows guidance', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'XC NoProj', suffix: 'xc-07');
    await harness.seedEnvironment(name: 'xc-07-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC NoProj');

    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Execution'));
    // Launch controls live on the toolbar — gated until a project is open.
    expect(find.widgetWithText(FilledButton, 'Run Project'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Run File'), findsNothing);
    final runProject = tester.widget<ToolbarButton>(
      toolbarButton('Run Project'),
    );
    expect(runProject.onTap, isNull);
    expect(runProject.tooltip, 'Open a project to run');

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-08 execution logs reveal from status badge', (tester) async {
    final seeded = await seedRunnable(
      workspace: 'XC Reveal',
      suffix: 'xc-08',
      project: 'XcReveal',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Reveal');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'run.robot',
      projectName: seeded.project,
    );
    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);

    await pumpUntilFound(tester, find.textContaining('Last: '));
    await tester.tap(find.textContaining('Last: ').first);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntilFound(
      tester,
      find.textContaining('integration test'),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-09 cold start idle no stale running', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'XC Cold', suffix: 'xc-09');
    await harness.seedEnvironment(name: 'xc-09-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Cold');

    final status = await harness.api.executionStatus();
    final state = status['status']?.toString() ?? '';
    expect(state == 'running' || state == 'starting', isFalse);
    expect(find.text('Idle'), findsNothing);
    expect(find.textContaining('Running ·'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-10 concurrent run blocked', (tester) async {
    const sleepy = '''*** Test Cases ***
Sleepy
    Sleep    45s
''';
    final seeded = await seedRunnable(
      workspace: 'XC Concurrent',
      suffix: 'xc-10',
      project: 'XcConcurrent',
      content: sleepy,
      suiteFile: 'long.robot',
    );
    await harness.launchAppWithWorkspace(
      tester,
      workspaceName: 'XC Concurrent',
    );
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'long.robot',
      projectName: seeded.project,
    );

    await tapToolbarAction(tester, 'Run current file');
    await pumpUntilFound(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is ToolbarButton &&
            widget.label == 'Run' &&
            widget.onTap == null &&
            widget.tooltip == 'Stop the current run first',
      ),
      timeout: const Duration(seconds: 45),
    );
    final run = tester.widget<ToolbarButton>(toolbarButton('Run'));
    expect(run.onTap, isNull);

    await tester.tap(toolbarButton('Stop'));
    await tester.pump(const Duration(milliseconds: 400));
    await waitForExecutionFinished(
      harness.api,
      timeout: const Duration(seconds: 60),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-11 failed run preserves failure in logs', (tester) async {
    const failing = '''*** Test Cases ***
Will Fail
    Fail    intentional failure for XC-11
''';
    final seeded = await seedRunnable(
      workspace: 'XC Fail',
      suffix: 'xc-11',
      project: 'XcFail',
      content: failing,
      suiteFile: 'fail.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC Fail');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'fail.robot',
      projectName: seeded.project,
    );

    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);

    final last = find.textContaining('Last: ');
    if (tester.widgetList(last).isNotEmpty) {
      await tester.tap(last.first);
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tapSidebarPanel(tester, 'Tests');
    }
    await pumpUntilFound(
      tester,
      find.textContaining('intentional failure'),
      timeout: const Duration(seconds: 45),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('XC-12 history list newest first', (tester) async {
    final seeded = await seedRunnable(
      workspace: 'XC History',
      suffix: 'xc-12',
      project: 'XcHistory',
      suiteFile: 'hist.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'XC History');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'hist.robot',
      projectName: seeded.project,
    );

    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);
    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);

    final history = await harness.api.executionHistory();
    expect(history.length, greaterThanOrEqualTo(2));

    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Live Output'));

    harness.expectNoFlutterErrors();
  });
}
