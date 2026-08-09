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

  testWidgets('repeated panel switching and project creation remains stable', (
    tester,
  ) async {
    await harness.seedWorkspace(name: 'Regression A', suffix: 'reg-a');
    await harness.seedEnvironment(name: 'regression-env', installRobot: false);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Regression A');

    for (var i = 0; i < 3; i++) {
      await tapSidebarPanel(tester, 'Explorer');
      await tapSidebarPanel(tester, 'Packages');
      await tapSidebarPanel(tester, 'Source Control');
      await tapSidebarPanel(tester, 'Explorer');
      await createProjectViaUi(tester, name: 'Temp Project $i');
      await pumpUntilFound(tester, find.text('Temp Project $i'));
    }

    harness.expectNoFlutterErrors();
  });

  testWidgets('repeated execution and environment activation', (tester) async {
    await harness.seedWorkspace(name: 'Regression Exec', suffix: 'reg-exec');
    await harness.seedEnvironment(
      name: 'regression-exec-env',
      installRobot: true,
    );
    final project = await harness.seedProject(name: 'ExecProject');
    final suite = '${project['path']}/tests/regression.robot';
    await harness.api.writeFile(
      path: suite,
      content: '*** Test Cases ***\nR\n    Log    ok\n',
    );

    await harness.launchAppWithWorkspace(
      tester,
      workspaceName: 'Regression Exec',
    );

    // Opening the workspace from the UI clears the backend project session.
    await harness.api.openProject(project['id'] as String);

    for (var i = 0; i < 2; i++) {
      final envs = await harness.api.listEnvironments();
      final target = envs.first;
      await harness.api.activateEnvironment(target['id'] as String);
      await harness.api.runFile(suite);
      await waitForExecutionFinished(harness.api);
    }

    harness.expectNoFlutterErrors();
  });
}
