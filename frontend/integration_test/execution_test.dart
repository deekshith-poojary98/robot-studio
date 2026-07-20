import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_fixtures.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('run robot test updates console, history, and reports', (tester) async {
    await harness.seedWorkspace(name: 'Execution Flow WS', suffix: 'execution');
    await harness.seedEnvironment(name: 'execution-env', installRobot: true);

    final project = await harness.seedProject(name: 'ExecutionProject');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/run.robot';
    Directory('$projectPath/tests').createSync(recursive: true);
    File(suitePath).writeAsStringSync(IntegrationFixtures.sampleRobot);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Execution Flow WS');

    await openProjectInExplorer(tester, projectName: 'ExecutionProject');
    await openRobotFileInExplorer(tester, 'run.robot');

    await harness.performance.measureAsync(
      'execution_startup',
      () async {
        await tapToolbarAction(tester, 'Run');
        final status = await waitForExecutionFinished(harness.api);
        expect(status['status'], 'finished');
        return status;
      },
    );

    await openBottomTab(tester, 'Execution Logs');
    await pumpUntilFound(tester, find.textContaining('integration test'));

    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Recent Runs'));

    final history = await harness.api.executionHistory();
    expect(history, isNotEmpty);

    final reports = await harness.api.listReports();
    expect(reports, isNotEmpty);

    harness.expectNoFlutterErrors();
  });
}
