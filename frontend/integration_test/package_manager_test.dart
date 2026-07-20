import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('search, install, and uninstall lightweight package', (tester) async {
    await harness.seedWorkspace(name: 'Package Flow WS', suffix: 'packages');
    await harness.seedEnvironment(
      name: 'package-env',
      installRobot: false,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'Package Flow WS');

    await openPackageManager(tester);
    await pumpUntilFound(tester, find.text('Package Manager'));

    final searchResults = await harness.api.searchPackages('six');
    expect(searchResults['results'], isNotEmpty);

    await harness.api.installPackage('six');
    var packages = await harness.api.listPackages();
    expect(packages.any((item) => item['name'] == 'six'), isTrue);

    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, find.text('six'), timeout: const Duration(seconds: 30));

    await harness.api.uninstallPackage('six');
    packages = await harness.api.listPackages();
    expect(packages.any((item) => item['name'] == 'six'), isFalse);

    harness.expectNoFlutterErrors();
  });

  testWidgets('robot framework detection updates after install env', (tester) async {
    await harness.seedWorkspace(name: 'Robot Detect WS', suffix: 'robot-detect');
    await harness.seedEnvironment(
      name: 'robot-detect-env',
      installRobot: true,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'Robot Detect WS');

    await openPackageManager(tester);
    await pumpUntilFound(
      tester,
      find.textContaining('Robot'),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });
}
