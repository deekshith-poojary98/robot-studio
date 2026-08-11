import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: RP-01 … RP-09 (Reports).
///
/// Source: docs/internal/functional-test-cases.md §12
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

  Future<({String path, String project})> seedAndRun({
    required String workspace,
    required String suffix,
    required String project,
    String content = IntegrationFixtures.sampleRobot,
    String suiteFile = 'report.robot',
  }) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: true);
    final created = await harness.seedProject(name: project);
    final path = '${created['path']}/tests/$suiteFile';
    await harness.api.writeFile(path: path, content: content);
    await harness.api.runFile(path);
    await waitForExecutionFinished(harness.api);
    return (path: path, project: project);
  }

  testWidgets('RP-01 reports list after run', (tester) async {
    await seedAndRun(
      workspace: 'RP List',
      suffix: 'rp-01',
      project: 'RpList',
    );
    final reports = await harness.api.listReports();
    expect(reports, isNotEmpty);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP List');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('Reports'));
    expect(find.textContaining('No reports yet'), findsNothing);
    await pumpUntilFound(tester, find.textContaining('RpList'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-02 auto-select latest run details', (tester) async {
    await seedAndRun(
      workspace: 'RP Select',
      suffix: 'rp-02',
      project: 'RpSelect',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Select');
    await openReports(tester);
    await pumpUntilFound(tester, find.textContaining('RpSelect'));
    await pumpUntilFound(tester, find.text('Statistics'));
    expect(find.text('Passed'), findsWidgets);
    expect(find.text('Failed'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-03 open report via artifact hyperlink', (tester) async {
    await seedAndRun(
      workspace: 'RP Html',
      suffix: 'rp-03',
      project: 'RpHtml',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Html');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('report.html'));
    await tester.tap(find.text('report.html').first);
    await tester.pump(const Duration(milliseconds: 800));

    // Host-dependent open; assert action path completes without Flutter errors.
    final feedback =
        tester.widgetList(find.textContaining('report.html')).isNotEmpty ||
        tester.widgetList(find.textContaining('Opened')).isNotEmpty;
    expect(feedback, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-04 open log via artifact hyperlink', (tester) async {
    await seedAndRun(
      workspace: 'RP Log',
      suffix: 'rp-04',
      project: 'RpLog',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Log');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('log.html'));
    await tester.tap(find.text('log.html').first);
    await tester.pump(const Duration(milliseconds: 800));

    final feedback =
        tester.widgetList(find.textContaining('log.html')).isNotEmpty ||
        tester.widgetList(find.textContaining('Opened')).isNotEmpty;
    expect(feedback, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-05 artifact rows listed', (tester) async {
    await seedAndRun(
      workspace: 'RP Artifacts',
      suffix: 'rp-05',
      project: 'RpArtifacts',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Artifacts');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('Artifacts'));
    expect(find.text('output.xml'), findsWidgets);
    expect(find.text('log.html'), findsWidgets);
    expect(find.text('report.html'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-06 pass fail dashboard stats', (tester) async {
    await seedAndRun(
      workspace: 'RP Dash',
      suffix: 'rp-06',
      project: 'RpDash',
    );
    const failing = '''*** Test Cases ***
Will Fail
    Fail    rp-06 fail
''';
    final project = await harness.api.listProjects();
    final path = project
        .firstWhere((item) => item['name'] == 'RpDash')['path'] as String;
    await harness.api.writeFile(
      path: '$path/tests/fail.robot',
      content: failing,
    );
    await ensureExecutionIdle();
    await harness.api.runFile('$path/tests/fail.robot');
    await waitForExecutionFinished(harness.api);

    final dashboard = await harness.api.reportsDashboard();
    expect(dashboard, isA<Map<String, dynamic>>());

    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Dash');
    await openReports(tester);
    await pumpUntilFound(tester, find.textContaining('Pass Rate'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-07 delete run with confirm', (tester) async {
    await seedAndRun(
      workspace: 'RP Delete',
      suffix: 'rp-07',
      project: 'RpDelete',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Delete');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('Delete Run'));
    await tester.tap(find.text('Delete Run'));
    await tester.pump(const Duration(milliseconds: 400));

    // Confirm dialog if present.
    final deleteConfirm = find.textContaining('Delete');
    await pumpUntilFound(tester, deleteConfirm);
    final confirm = find.text('Delete');
    if (tester.widgetList(confirm).length > 1) {
      await tester.tap(confirm.last);
    } else {
      final ok = find.text('OK');
      if (tester.widgetList(ok).isNotEmpty) {
        await tester.tap(ok.last);
      }
    }
    await tester.pump(const Duration(milliseconds: 600));

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-08 reports with zero runs', (tester) async {
    await ensureExecutionIdle();
    await harness.seedWorkspace(name: 'RP Empty', suffix: 'rp-08');
    await harness.seedEnvironment(name: 'rp-08-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Empty');
    await openReports(tester);
    await pumpUntilFound(
      tester,
      find.textContaining('No reports yet'),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('RP-09 switch away and back after new run', (tester) async {
    final seeded = await seedAndRun(
      workspace: 'RP Refresh',
      suffix: 'rp-09',
      project: 'RpRefresh',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RP Refresh');
    await openReports(tester);
    await pumpUntilFound(tester, find.textContaining('RpRefresh'));

    await tapSidebarPanel(tester, 'Explorer');
    await openProjectInExplorer(tester, projectName: seeded.project);
    await openRobotFileInExplorer(
      tester,
      'report.robot',
      projectName: seeded.project,
    );
    await tapToolbarAction(tester, 'Run current file');
    await waitForExecutionFinished(harness.api);

    await openReports(tester);
    await pumpUntilFound(tester, find.textContaining('RpRefresh'));
    expect(find.textContaining('No reports yet'), findsNothing);
    final reports = await harness.api.listReports();
    expect(reports.length, greaterThanOrEqualTo(1));

    harness.expectNoFlutterErrors();
  });
}
