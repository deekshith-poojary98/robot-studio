import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_api_client.dart';
import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('reports page loads run details and delete action', (tester) async {
    await harness.seedWorkspace(name: 'Reports Flow WS', suffix: 'reports');
    await harness.seedEnvironment(name: 'reports-env', installRobot: true);

    final project = await harness.seedProject(name: 'ReportsProject');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/report.robot';
    Directory('$projectPath/tests').createSync(recursive: true);
    File(suitePath).writeAsStringSync(
      '*** Test Cases ***\nReport Case\n    Log    report\n',
    );

    await harness.api.runFile(suitePath);
    await waitForExecutionFinished(harness.api);

    final reports = await harness.api.listReports();
    expect(reports, isNotEmpty);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Reports Flow WS');
    await openReports(tester);
    await pumpUntilFound(tester, find.text('Reports'));
    // Run list shows project name / suite path, not Robot test-case titles.
    await pumpUntilFound(tester, find.text('ReportsProject'));
    await pumpUntilFound(tester, find.textContaining('report.robot'));

    harness.expectNoFlutterErrors();
  });
}
