import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: PR-01 … PR-10 (Project).
///
/// Source: Robot Studio — Functional Test Cases.md §3
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('PR-01 create project appears in explorer',
      (tester) async {
    await harness.seedWorkspace(name: 'PR Create', suffix: 'pr-01');
    await harness.seedEnvironment(name: 'pr-01-env', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Create');

    const projectName = 'PR New';
    await createProjectViaUi(tester, name: projectName);
    await pumpUntilFound(tester, find.text(projectName));

    final projects = await harness.api.listProjects();
    expect(projects.any((item) => item['name'] == projectName), isTrue);

    await openProjectInExplorer(tester, projectName: projectName);
    expect(find.text('TYPE'), findsOneWidget);
    expect(find.text('LOCATION'), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-02 duplicate project name is rejected', (tester) async {
    await harness.seedWorkspace(name: 'PR Dup', suffix: 'pr-02');
    await harness.seedProject(name: 'Amazon');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Dup');

    await tapTooltip(tester, 'New Project');
    await pumpUntilFound(tester, find.text('New Project', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Project name', 'Amazon');
    await submitDialog(tester, actionLabel: 'Create');

    await pumpUntilFound(
      tester,
      find.textContaining('exists'),
      timeout: const Duration(seconds: 15),
    );
    await dismissErrorDialogIfPresent(tester);

    final projects = await harness.api.listProjects();
    expect(
      projects.where((item) => item['name'] == 'Amazon').length,
      1,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-03 empty project name blocked', (tester) async {
    await harness.seedWorkspace(name: 'PR Empty', suffix: 'pr-03');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Empty');

    await tapTooltip(tester, 'New Project');
    await pumpUntilFound(tester, find.text('New Project', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Project name', '');
    await submitDialog(tester, actionLabel: 'Create');
    await tester.pump(const Duration(milliseconds: 400));

    // Dialog should remain (validation) — no new project created.
    expect(find.text('New Project'), findsWidgets);
    final projects = await harness.api.listProjects();
    expect(projects, isEmpty);

    // Cancel to clean up.
    final cancel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Cancel'),
    );
    if (tester.widgetList(cancel).isNotEmpty) {
      await tester.tap(cancel.last);
      await tester.pump();
    }

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-04 import existing project tree', (tester) async {
    await harness.seedWorkspace(name: 'PR Import', suffix: 'pr-04');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Import');

    final importRoot = harness.resources.scratch('pr-import-me');
    importRoot.createSync(recursive: true);
    Directory('${importRoot.path}/tests').createSync(recursive: true);
    File('${importRoot.path}/tests/sample.robot').writeAsStringSync(
      '*** Test Cases ***\nSample\n    Log    x\n',
    );

    await tapTooltip(tester, 'Import Project');
    await pumpUntilFound(tester, find.text('Import Project', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Project path', importRoot.path);
    await submitDialog(tester, actionLabel: 'Import');
    await pumpUntilAbsent(tester, find.text('Import Project'));

    await pumpUntilFound(tester, find.text('pr-import-me'));
    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-05 select project updates details', (tester) async {
    await harness.seedWorkspace(name: 'PR Select', suffix: 'pr-05');
    await harness.seedProject(name: 'ProjA');
    await harness.seedProject(name: 'ProjB');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Select');

    await openProjectInExplorer(tester, projectName: 'ProjA');
    expect(find.text('ProjA'), findsWidgets);

    await openProjectInExplorer(tester, projectName: 'ProjB');
    expect(find.text('ProjB'), findsWidgets);
    expect(find.text('TYPE'), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-06 auto-selects a project on workspace open', (tester) async {
    await harness.seedWorkspace(name: 'PR Auto', suffix: 'pr-06');
    await harness.seedProject(name: 'AutoPick');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Auto');

    // Auto-select should surface project details or Continue CTA / selection.
    await pumpUntilFound(
      tester,
      find.textContaining('AutoPick'),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-07 project details show location', (tester) async {
    await harness.seedWorkspace(name: 'PR Details', suffix: 'pr-07');
    final project = await harness.seedProject(name: 'DetailProj');
    final path = project['path'] as String;

    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Details');
    await openProjectInExplorer(tester, projectName: 'DetailProj');

    expect(find.text('TYPE'), findsNothing);
    expect(find.text('LOCATION'), findsOneWidget);
    // Path basename or full path fragment should appear.
    expect(
      find.textContaining('DetailProj'),
      findsWidgets,
    );
    expect(path.isNotEmpty, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-08 cancel create leaves no partial project', (tester) async {
    await harness.seedWorkspace(name: 'PR Cancel', suffix: 'pr-08');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Cancel');

    await tapTooltip(tester, 'New Project');
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await fillDialogFieldByLabel(tester, 'Project name', 'ShouldNotExist');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ).last,
    );
    await tester.pump();
    await pumpUntilAbsent(tester, find.byType(AlertDialog));

    final projects = await harness.api.listProjects();
    expect(
      projects.any((item) => item['name'] == 'ShouldNotExist'),
      isFalse,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-09 run without environment shows guidance', (tester) async {
    await harness.seedWorkspace(name: 'PR NoEnv', suffix: 'pr-09');
    await harness.seedProject(name: 'NeedsEnv');
    // No environment seeded / activated.
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR NoEnv');
    await openProjectInExplorer(tester, projectName: 'NeedsEnv');

    // Enabled Run Project tooltip (not the label text).
    final runProject = find.byTooltip('Run the selected project');
    await pumpUntilFound(tester, runProject);
    await tester.tap(runProject.first);
    await tester.pump();

    await pumpUntilFound(
      tester,
      find.byType(AlertDialog),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.textContaining('environment'),
      findsWidgets,
    );

    // Dismiss guidance.
    final cancel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Cancel'),
    );
    if (tester.widgetList(cancel).isNotEmpty) {
      await tester.tap(cancel.last);
      await tester.pump();
    } else {
      await dismissErrorDialogIfPresent(tester);
    }

    harness.expectNoFlutterErrors();
  });

  testWidgets('PR-10 open project from explorer after workspace open',
      (tester) async {
    await harness.seedWorkspace(name: 'PR Continue', suffix: 'pr-10');
    await harness.seedProject(name: 'ContinueMe');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PR Continue');

    expect(find.textContaining('Continue with'), findsNothing);
    await openProjectInExplorer(tester, projectName: 'ContinueMe');

    await pumpUntilFound(tester, find.text('TYPE'));
    harness.expectNoFlutterErrors();
  });
}
