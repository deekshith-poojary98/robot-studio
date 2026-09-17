import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: RC-01 … RC-04 (Run configurations).
///
/// Source: docs/internal/functional-test-cases.md §20
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<void> seedMinimal({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: false);
    await harness.seedProject(name: project);
  }

  testWidgets('RC-01 run configuration chip shows Default', (tester) async {
    await seedMinimal(
      workspace: 'RC Default',
      suffix: 'rc-01',
      project: 'RcDefault',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RC Default');
    await openProjectInExplorer(tester, projectName: 'RcDefault');

    await pumpUntilFound(
      tester,
      find.byKey(const Key('toolbar.run-configuration')),
    );
    expect(find.text('Default'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('RC-02 open new configuration dialog', (tester) async {
    await seedMinimal(
      workspace: 'RC New',
      suffix: 'rc-02',
      project: 'RcNew',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RC New');
    await openProjectInExplorer(tester, projectName: 'RcNew');

    await openRunConfigurationMenu(tester);
    await tapText(tester, 'New Configuration…');
    await pumpUntilFound(tester, find.text('New Run Configuration'));
    expect(find.text('Name'), findsWidgets);
    expect(find.text('Create'), findsWidgets);

    await tapText(tester, 'Cancel');
    await pumpUntilAbsent(tester, find.text('New Run Configuration'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('RC-03 create a named run configuration', (tester) async {
    await seedMinimal(
      workspace: 'RC Create',
      suffix: 'rc-03',
      project: 'RcCreate',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RC Create');
    await openProjectInExplorer(tester, projectName: 'RcCreate');

    await openRunConfigurationMenu(tester);
    await tapText(tester, 'New Configuration…');
    await pumpUntilFound(tester, find.text('New Run Configuration'));

    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await pumpUntilFound(tester, nameField);
    await tester.enterText(nameField.first, 'Smoke Tags');
    await tester.pump(const Duration(milliseconds: 200));

    await submitDialog(tester, actionLabel: 'Create');
    await pumpUntilAbsent(tester, find.text('New Run Configuration'));

    await pumpUntilFound(tester, find.text('Smoke Tags'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('RC-04 manage configurations dialog', (tester) async {
    await seedMinimal(
      workspace: 'RC Manage',
      suffix: 'rc-04',
      project: 'RcManage',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'RC Manage');
    await openProjectInExplorer(tester, projectName: 'RcManage');

    await openRunConfigurationMenu(tester);
    await tapText(tester, 'Manage Configurations…');
    await pumpUntilFound(tester, find.text('Run Configurations'));

    // Close via Done.
    final done = find.text('Done');
    await pumpUntilFound(tester, done);
    await tester.tap(done.first);
    await tester.pump(const Duration(milliseconds: 400));

    harness.expectNoFlutterErrors();
  });
}
