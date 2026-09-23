import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: DR-01 … DR-04 (Robot Doctor).
///
/// Source: docs/internal/functional-test-cases.md §18
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<void> seedDoctorProject({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: false);
    final created = await harness.seedProject(name: project);
    final root = created['path'] as String;
    await harness.api.writeFile(
      path: '$root/resources/common.resource',
      content: '*** Keywords ***\n'
          'Login User\n'
          '    Log    login\n'
          '\n'
          'Dead Keyword\n'
          '    No Operation\n',
    );
    await harness.api.writeFile(
      path: '$root/tests/login.robot',
      content: '*** Settings ***\n'
          'Resource    ../resources/common.resource\n'
          '*** Test Cases ***\n'
          'Can Login\n'
          '    Login User\n',
    );
    await harness.api.rebuildIndex(wait: true);
  }

  testWidgets('DR-01 open doctor from activity rail', (tester) async {
    await seedDoctorProject(
      workspace: 'DR Rail',
      suffix: 'dr-01',
      project: 'DrRail',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'DR Rail');
    await openProjectInExplorer(tester, projectName: 'DrRail');
    await openDoctor(tester);

    expect(find.text('Robot Doctor'), findsOneWidget);
    expect(find.textContaining('Scan'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('DR-02 open doctor from command palette', (tester) async {
    await seedDoctorProject(
      workspace: 'DR Palette',
      suffix: 'dr-02',
      project: 'DrPalette',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'DR Palette');
    await openProjectInExplorer(tester, projectName: 'DrPalette');
    await runCommandPaletteAction(tester, 'Open Robot Doctor');
    await pumpUntilFound(tester, find.text('Robot Doctor'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('DR-03 auto-scan surfaces unused keyword', (tester) async {
    await seedDoctorProject(
      workspace: 'DR Unused',
      suffix: 'dr-03',
      project: 'DrUnused',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'DR Unused');
    await openProjectInExplorer(tester, projectName: 'DrUnused');
    await openDoctor(tester);

    await pumpUntilFound(
      tester,
      find.textContaining('Dead Keyword'),
      timeout: const Duration(seconds: 60),
    );
    expect(find.textContaining('unused'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('DR-04 open source from finding', (tester) async {
    await seedDoctorProject(
      workspace: 'DR Jump',
      suffix: 'dr-04',
      project: 'DrJump',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'DR Jump');
    await openProjectInExplorer(tester, projectName: 'DrJump');
    await openDoctor(tester);

    final finding = find.textContaining('Dead Keyword');
    await pumpUntilFound(tester, finding, timeout: const Duration(seconds: 60));
    await tester.tap(finding.first);
    await tester.pump(const Duration(milliseconds: 400));

    final openSource = find.byKey(const Key('doctor-open-source'));
    await pumpUntilFound(tester, openSource);
    await tester.tap(openSource);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    expect(find.textContaining('common.resource'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
