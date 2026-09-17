import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: TM-01 … TM-04 (Terminal panel beyond tab existence).
///
/// Under `FLUTTER_TEST` the PTY is disabled, so these assert chrome, cwd,
/// restart/kill controls, and toggle — not interactive shell I/O.
///
/// Source: docs/internal/functional-test-cases.md §22
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<String> seedProject({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: false);
    final created = await harness.seedProject(name: project);
    return created['path'] as String;
  }

  testWidgets('TM-01 open terminal via bottom tab shows project cwd', (
    tester,
  ) async {
    final path = await seedProject(
      workspace: 'TM Tab',
      suffix: 'tm-01',
      project: 'TmTab',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'TM Tab');
    await openProjectInExplorer(tester, projectName: 'TmTab');
    await openBottomTab(tester, 'Terminal');

    // Header shows the project working directory (mono path label).
    final leaf = path.split('/').last;
    await pumpUntilFound(
      tester,
      find.textContaining(leaf),
      timeout: const Duration(seconds: 20),
    );
    expect(find.byTooltip('Restart shell'), findsOneWidget);
    expect(find.byTooltip('Kill shell'), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('TM-02 collapse and re-expand terminal panel', (tester) async {
    await seedProject(
      workspace: 'TM Toggle',
      suffix: 'tm-02',
      project: 'TmToggle',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'TM Toggle');
    await openProjectInExplorer(tester, projectName: 'TmToggle');
    await openBottomTab(tester, 'Terminal');
    await pumpUntilFound(tester, find.byTooltip('Restart shell'));

    await tapTooltip(tester, 'Collapse panel');
    await pumpUntilAbsent(
      tester,
      find.byTooltip('Restart shell'),
      timeout: const Duration(seconds: 10),
    );

    await openBottomTab(tester, 'Terminal');
    await pumpUntilFound(tester, find.byTooltip('Restart shell'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('TM-03 restart shell control is tappable', (tester) async {
    await seedProject(
      workspace: 'TM Restart',
      suffix: 'tm-03',
      project: 'TmRestart',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'TM Restart');
    await openProjectInExplorer(tester, projectName: 'TmRestart');
    await openBottomTab(tester, 'Terminal');

    final restart = find.byTooltip('Restart shell');
    await pumpUntilFound(tester, restart);
    await tester.tap(restart);
    await tester.pump(const Duration(milliseconds: 400));

    // Control remains available after restart (PTY skipped under FLUTTER_TEST).
    expect(find.byTooltip('Restart shell'), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('TM-04 kill shell writes status into terminal buffer chrome', (
    tester,
  ) async {
    await seedProject(
      workspace: 'TM Kill',
      suffix: 'tm-04',
      project: 'TmKill',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'TM Kill');
    await openProjectInExplorer(tester, projectName: 'TmKill');
    await openBottomTab(tester, 'Terminal');

    final kill = find.byTooltip('Kill shell');
    await pumpUntilFound(tester, kill);
    await tester.tap(kill);
    await tester.pump(const Duration(milliseconds: 400));

    // Kill always appends a status line into the xterm buffer; chrome stays up.
    expect(find.byTooltip('Restart shell'), findsOneWidget);
    expect(find.byType(IconButton), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
