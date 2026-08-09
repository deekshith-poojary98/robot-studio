import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: SH-01 … SH-08 (Shell / Status / Connectivity).
///
/// Source: Robot Studio — Functional Test Cases.md §1
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('SH-01 cold start with backend up shows welcome', (tester) async {
    await harness.launchApp(tester);

    expect(find.text('Robot Studio'), findsWidgets);
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'SH-02 cold start with backend down shows waiting state '
    '[skipped: needs dead backend URL without script-started server]',
    (tester) async {},
    skip: true,
  );

  testWidgets(
    'SH-03 backend reconnect recovers without chrome flicker '
    '[skipped: external backend cannot be stopped from harness]',
    (tester) async {},
    skip: true,
  );

  testWidgets('SH-04 status bar ROBOT PYTHON match active environment', (
    tester,
  ) async {
    await harness.seedWorkspace(name: 'SH Status', suffix: 'sh-status');
    await harness.seedEnvironment(name: 'sh-env', installRobot: true);
    await harness.seedProject(name: 'SHProj');

    await harness.launchAppWithWorkspace(tester, workspaceName: 'SH Status');

    await pumpUntilFound(
      tester,
      find.text('sh-env'),
      timeout: const Duration(seconds: 60),
    );
    expect(find.textContaining('ENV '), findsNothing);
    expect(find.text('ROBOT —'), findsNothing);
    expect(find.textContaining('ROBOT '), findsWidgets);
    expect(find.textContaining('PYTHON '), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('SH-05 status bar ERRORS opens Problems panel', (tester) async {
    await harness.seedWorkspace(name: 'SH Problems', suffix: 'sh-problems');
    // Robot required so the parser emits unknown-keyword diagnostics.
    await harness.seedEnvironment(name: 'sh-prob', installRobot: true);

    final project = await harness.seedProject(name: 'SHProb');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/sample.robot';
    const broken = '*** Test Cases ***\nBroken\n    UnknownKeyword    x\n';
    await harness.api.writeFile(path: suitePath, content: broken);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'SH Problems');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'SHProb',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('editor.page')),
      timeout: const Duration(seconds: 30),
    );

    // Allow live language refresh (debounced) to populate Problems.
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(
      tester,
      find.textContaining('PROBLEMS '),
      timeout: const Duration(seconds: 90),
    );

    final problemsChrome = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          (widget.data!.startsWith('ERRORS ') ||
              widget.data!.startsWith('WARNINGS ')),
    );
    await pumpUntilFound(
      tester,
      problemsChrome,
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(problemsChrome.first);
    await tester.pump();

    await pumpUntilFound(
      tester,
      find.textContaining('UnknownKeyword'),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('SH-06 activity rail tooltips are descriptive', (tester) async {
    await harness.launchApp(tester);

    final expected = <String>[
      'Explorer — projects, environments, and files',
      'Search — find text across the project',
      'Insights — project composition and run health',
      'Tests — browse, run, and track suites and tests',
      'Packages — install and manage Python packages',
      'Plugins — built-in and project extensions',
      'Source Control — Git status, commit, and branches',
      'Reports — run history, logs, and HTML reports',
    ];

    for (final tooltip in expected) {
      expect(
        find.byTooltip(tooltip),
        findsOneWidget,
        reason: 'Missing tooltip: $tooltip',
      );
    }

    harness.expectNoFlutterErrors();
  });

  testWidgets('SH-07 view switching does not stick prior empty state', (
    tester,
  ) async {
    await harness.seedWorkspace(name: 'SH Views', suffix: 'sh-views');
    await harness.seedEnvironment(name: 'sh-views', installRobot: false);
    await harness.seedProject(name: 'SHView');

    await harness.launchAppWithWorkspace(tester, workspaceName: 'SH Views');

    await openSourceControl(tester);
    expect(find.textContaining('Git'), findsWidgets);

    await openReports(tester);
    expect(find.text('Reports'), findsWidgets);

    await openPackageManager(tester);
    expect(find.text('Package Manager'), findsWidgets);

    await tapSidebarPanel(tester, 'Explorer');
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilFound(tester, find.textContaining('SHView'));

    // Explorer keeps a "Package Manager" shortcut; the full page must close.
    expect(find.text('Package Manager'), findsOneWidget);
    expect(find.textContaining('SHView'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('SH-08 bottom panel exposes only implemented tabs', (
    tester,
  ) async {
    await harness.seedWorkspace(name: 'SH Bottom', suffix: 'sh-bottom');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'SH Bottom');

    await openBottomTab(tester, 'Problems');
    await openBottomTab(tester, 'Terminal');
    expect(find.text('Console'), findsNothing);
    expect(find.text('OUTPUT'), findsNothing);
    expect(find.text('EXECUTION LOGS'), findsNothing);

    harness.expectNoFlutterErrors();
  });
}
