import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/performance_tracker.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('create, activate, clone, and delete environment', (tester) async {
    await harness.seedWorkspace(name: 'Env Flow WS', suffix: 'env-flow');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'Env Flow WS');

    await createEnvironmentViaUi(
      tester,
      name: 'it-env-ui',
      pythonInterpreter: defaultPythonInterpreter(),
      installRobot: false,
    );
    await pumpUntilFound(
      tester,
      find.text('it-env-ui'),
      timeout: const Duration(minutes: 3),
    );

    final env = await harness.performance.measureAsync(
      'environment_create_api',
      () => harness.api.createEnvironment(
        name: 'it-env-api',
        pythonInterpreter: defaultPythonInterpreter(),
        installRobotFramework: false,
      ),
    );

    final activated = await harness.performance.measureAsync(
      'environment_activation',
      () => harness.api.activateEnvironment(env['id'] as String),
    );
    expect(activated['active'], isTrue);

    await refreshEnvironmentsInUi(tester);
    await pumpUntilFound(tester, find.textContaining('it-env-api'));

    final cloned = await harness.api.cloneEnvironment(
      id: env['id'] as String,
      name: 'it-env-clone',
    );
    expect(cloned['name'], 'it-env-clone');

    final envs = await harness.api.listEnvironments();
    expect(envs.any((item) => item['name'] == 'it-env-clone'), isTrue);

    final uiEnvId = envs.firstWhere((item) => item['name'] == 'it-env-ui')['id'] as String;

    // Backend forbids deleting the active environment — switch to a keeper first.
    await harness.api.activateEnvironment(uiEnvId);
    await harness.api.deleteEnvironment(env['id'] as String);
    await harness.api.deleteEnvironment(cloned['id'] as String);

    harness.expectNoFlutterErrors();
  });
}
