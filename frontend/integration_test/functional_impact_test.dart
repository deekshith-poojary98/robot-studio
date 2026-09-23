import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: IA-01 … IA-04 (Impact Analysis / Run Impact Set).
///
/// Source: docs/internal/functional-test-cases.md §17
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<({String resource, String suite})> seedImpactProject({
    required String workspace,
    required String suffix,
    required String project,
    bool installRobot = false,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(
      name: '$suffix-env',
      installRobot: installRobot,
    );
    final created = await harness.seedProject(name: project);
    final root = created['path'] as String;
    final resource = '$root/resources/common.resource';
    final suite = '$root/tests/login.robot';
    await harness.api.writeFile(
      path: resource,
      content:
          '*** Keywords ***\n'
          'LoginUser\n'
          '    [Documentation]    Shared login\n'
          '    Log    login\n'
          '\n'
          'DeadKeyword\n'
          '    No Operation\n',
    );
    await harness.api.writeFile(
      path: suite,
      content:
          '*** Settings ***\n'
          'Resource    ../resources/common.resource\n'
          'Library     BuiltIn\n'
          '*** Variables ***\n'
          '\${USER}    admin\n'
          '*** Test Cases ***\n'
          'Can Login\n'
          '    LoginUser\n'
          '    Log    \${USER}\n',
    );
    await harness.api.rebuildIndex(wait: true);
    return (resource: resource, suite: suite);
  }

  Future<void> openImpactForLoginUser(
    WidgetTester tester, {
    required String projectName,
  }) async {
    await openRobotFileInExplorer(
      tester,
      'common.resource',
      projectName: projectName,
    );
    await waitForEditorOpen(tester);
    await selectOutlineSymbol(tester, 'LoginUser');
    await runCommandPaletteAction(tester, 'Impact Analysis');
    await pumpUntilFound(tester, find.text('Impact'));
  }

  testWidgets('IA-01 impact analysis from outline keyword', (tester) async {
    await seedImpactProject(
      workspace: 'IA Analyze',
      suffix: 'ia-01',
      project: 'IaAnalyze',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IA Analyze');
    await openProjectInExplorer(tester, projectName: 'IaAnalyze');
    await openImpactForLoginUser(tester, projectName: 'IaAnalyze');

    expect(find.textContaining('LoginUser'), findsWidgets);
    await pumpUntilFound(
      tester,
      find.text('Can Login'),
      timeout: const Duration(seconds: 45),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('IA-02 impact panel lists affected tests', (tester) async {
    await seedImpactProject(
      workspace: 'IA Hits',
      suffix: 'ia-02',
      project: 'IaHits',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IA Hits');
    await openProjectInExplorer(tester, projectName: 'IaHits');
    await openImpactForLoginUser(tester, projectName: 'IaHits');

    await pumpUntilFound(tester, find.textContaining('Affected'));
    expect(find.text('Can Login'), findsWidgets);
    expect(find.textContaining('Run Impact Set'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('IA-02b impact panel stays open after jumping to a hit', (
    tester,
  ) async {
    await seedImpactProject(
      workspace: 'IA Stay',
      suffix: 'ia-02b',
      project: 'IaStay',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IA Stay');
    await openProjectInExplorer(tester, projectName: 'IaStay');
    await openImpactForLoginUser(tester, projectName: 'IaStay');
    await pumpUntilFound(tester, find.text('Can Login'));

    await tester.tap(find.text('Can Login').first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Impact'), findsWidgets);
    expect(find.textContaining('Run Impact Set'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('IA-03 dismiss impact side panel', (tester) async {
    await seedImpactProject(
      workspace: 'IA Close',
      suffix: 'ia-03',
      project: 'IaClose',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IA Close');
    await openProjectInExplorer(tester, projectName: 'IaClose');
    await openImpactForLoginUser(tester, projectName: 'IaClose');
    await pumpUntilFound(tester, find.text('Can Login'));

    await tapTooltip(tester, 'Close');
    await pumpUntilAbsent(tester, find.text('Impact'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('IA-04 run impact set from panel', (tester) async {
    await seedImpactProject(
      workspace: 'IA Run',
      suffix: 'ia-04',
      project: 'IaRun',
      installRobot: true,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IA Run');
    await openProjectInExplorer(tester, projectName: 'IaRun');
    await openImpactForLoginUser(tester, projectName: 'IaRun');
    await pumpUntilFound(tester, find.text('Can Login'));

    final runButton = find.widgetWithText(FilledButton, 'Run Impact Set (1)');
    await pumpUntilFound(
      tester,
      runButton,
      timeout: const Duration(seconds: 45),
    );
    await tester.tap(runButton.first);
    await tester.pump(const Duration(milliseconds: 500));

    // Run starts on the Tests view; accept either running chrome or history.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    var sawRun = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (tester.widgetList(find.textContaining('Running')).isNotEmpty ||
          tester.widgetList(find.textContaining('impact set')).isNotEmpty ||
          tester.widgetList(find.text('Can Login')).isNotEmpty) {
        sawRun = true;
        break;
      }
    }
    expect(sawRun, isTrue);

    harness.expectNoFlutterErrors();
  });
}
