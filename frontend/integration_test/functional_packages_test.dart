import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: PK-01 … PK-09 (Packages).
///
/// Source: docs/internal/functional-test-cases.md §6
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('PK-01 list installed packages', (tester) async {
    await harness.seedWorkspace(name: 'PK List', suffix: 'pk-01');
    await harness.seedEnvironment(name: 'pk-list-env', installRobot: true);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK List');

    await openPackageManager(tester);
    await pumpUntilFound(tester, find.text('Package Manager'));
    await pumpUntilFound(
      tester,
      find.textContaining('robotframework'),
      timeout: const Duration(seconds: 45),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('PK-02 search PyPI returns results', (tester) async {
    await harness.seedWorkspace(name: 'PK Search', suffix: 'pk-02');
    await harness.seedEnvironment(name: 'pk-search-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK Search');

    final results = await harness.api.searchPackages('six');
    expect(results['results'], isA<List<dynamic>>());
    expect((results['results'] as List).isNotEmpty, isTrue);

    await openPackageManager(tester);
    // UI search control if present.
    final searchField = find.byType(TextField);
    if (tester.widgetList(searchField).isNotEmpty) {
      await tester.enterText(searchField.first, 'six');
      await tester.pump(const Duration(milliseconds: 500));
    }

    harness.expectNoFlutterErrors();
  });

  testWidgets('PK-03 install lightweight package', (tester) async {
    await harness.seedWorkspace(name: 'PK Install', suffix: 'pk-03');
    await harness.seedEnvironment(name: 'pk-install-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK Install');

    await harness.api.installPackage('six');
    final packages = await harness.api.listPackages();
    expect(packages.any((item) => item['name'] == 'six'), isTrue);

    await openPackageManager(tester);
    await tapText(tester, 'Refresh');
    await pumpUntilFound(
      tester,
      find.text('six'),
      timeout: const Duration(seconds: 45),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'PK-04 update package '
    '[skipped: update availability is environment-dependent]',
    (tester) async {},
    skip: true,
  );

  testWidgets('PK-05 uninstall package', (tester) async {
    await harness.seedWorkspace(name: 'PK Uninstall', suffix: 'pk-05');
    await harness.seedEnvironment(name: 'pk-un-env', installRobot: false);
    await harness.api.installPackage('six');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK Uninstall');

    await harness.api.uninstallPackage('six');
    final packages = await harness.api.listPackages();
    expect(packages.any((item) => item['name'] == 'six'), isFalse);

    await openPackageManager(tester);
    await tapText(tester, 'Refresh');
    await tester.pump(const Duration(seconds: 2));
    // six may still appear in PyPI search UI; installed list should not claim it.
    harness.expectNoFlutterErrors();
  });

  testWidgets('PK-06 packages without env show guidance', (tester) async {
    await harness.seedWorkspace(name: 'PK NoEnv', suffix: 'pk-06');
    // No environment.
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK NoEnv');

    await openPackageManager(tester);
    await pumpUntilFound(tester, find.text('Package Manager'));
    expect(
      find.textContaining('environment'),
      findsWidgets,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'PK-07 offline PyPI failure '
    '[skipped: cannot reliably disable network in harness]',
    (tester) async {},
    skip: true,
  );

  testWidgets('PK-08 package details panel opens', (tester) async {
    await harness.seedWorkspace(name: 'PK Details', suffix: 'pk-08');
    await harness.seedEnvironment(name: 'pk-det-env', installRobot: false);
    await harness.api.installPackage('six');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PK Details');

    await openPackageManager(tester);
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, find.text('six'));
    await tester.tap(find.text('six').first);
    await tester.pump(const Duration(milliseconds: 500));

    // Details should surface name/version somewhere in the shell.
    expect(find.textContaining('six'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'PK-09 missing-library install from run failure '
    '[deferred to XC/execution functional suite]',
    (tester) async {},
    skip: true,
  );
}
