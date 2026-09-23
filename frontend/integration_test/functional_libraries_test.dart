import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: LB-01 … LB-03 (Libraries panel).
///
/// Source: docs/internal/functional-test-cases.md §21
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<void> seedWithLibraries({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: true);
    final created = await harness.seedProject(name: project);
    final root = created['path'] as String;
    await harness.api.writeFile(
      path: '$root/tests/sample.robot',
      content:
          '*** Settings ***\n'
          'Library     BuiltIn\n'
          '*** Test Cases ***\n'
          'Smoke\n'
          '    Log    hello\n',
    );
    await harness.api.rebuildIndex(wait: true);
  }

  testWidgets('LB-01 open libraries from activity rail', (tester) async {
    await seedWithLibraries(
      workspace: 'LB Open',
      suffix: 'lb-01',
      project: 'LbOpen',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LB Open');
    await openProjectInExplorer(tester, projectName: 'LbOpen');
    await openLibraries(tester);

    expect(find.text('LIBRARIES'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('LB-02 lists BuiltIn or project libraries', (tester) async {
    await seedWithLibraries(
      workspace: 'LB List',
      suffix: 'lb-02',
      project: 'LbList',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LB List');
    await openProjectInExplorer(tester, projectName: 'LbList');
    await openLibraries(tester);

    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var found = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (tester.widgetList(find.textContaining('BuiltIn')).isNotEmpty ||
          tester.widgetList(find.text('No libraries')).isNotEmpty) {
        found = true;
        break;
      }
    }
    expect(found, isTrue);
    // With robotframework installed, BuiltIn should appear.
    expect(find.textContaining('BuiltIn'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('LB-03 open library keywords', (tester) async {
    await seedWithLibraries(
      workspace: 'LB Kw',
      suffix: 'lb-03',
      project: 'LbKw',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LB Kw');
    await openProjectInExplorer(tester, projectName: 'LbKw');
    await openLibraries(tester);

    final builtin = find.textContaining('BuiltIn');
    await pumpUntilFound(tester, builtin, timeout: const Duration(seconds: 45));
    await tester.tap(builtin.first);
    await tester.pump(const Duration(milliseconds: 500));

    // Keyword list or filter field should appear after opening a library.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    var sawKeywords = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (tester.widgetList(find.textContaining('Log')).isNotEmpty ||
          tester.widgetList(find.byType(TextField)).isNotEmpty) {
        sawKeywords = true;
        break;
      }
    }
    expect(sawKeywords, isTrue);

    harness.expectNoFlutterErrors();
  });
}
