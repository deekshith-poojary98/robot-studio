import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: ST-01 … ST-04 (Settings preferences UI).
///
/// Source: docs/internal/functional-test-cases.md §19
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

  testWidgets('ST-01 open settings from rail', (tester) async {
    await seedMinimal(
      workspace: 'ST Open',
      suffix: 'st-01',
      project: 'StOpen',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ST Open');
    await openSettings(tester);

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Editor'), findsWidgets);
    expect(find.text('Execution'), findsWidgets);
    expect(find.text('Appearance'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('ST-02 switch categories and see section fields', (tester) async {
    await seedMinimal(
      workspace: 'ST Cats',
      suffix: 'st-02',
      project: 'StCats',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ST Cats');
    await openSettings(tester);

    await tapText(tester, 'Execution');
    await pumpUntilFound(tester, find.text('Large Run Threshold'));

    await tapText(tester, 'Appearance');
    await pumpUntilFound(tester, find.textContaining('Theme'));

    await tapText(tester, 'Editor');
    await pumpUntilFound(tester, find.text('Auto Save'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('ST-03 save a preference change', (tester) async {
    await seedMinimal(
      workspace: 'ST Save',
      suffix: 'st-03',
      project: 'StSave',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ST Save');
    await openSettings(tester);
    await pumpUntilFound(tester, find.text('Auto Save'));

    final autoSaveSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Auto Save'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );
    // Fall back to first visible Switch in the settings content.
    final target = tester.widgetList(autoSaveSwitch).isNotEmpty
        ? autoSaveSwitch
        : find.byType(Switch);
    await pumpUntilFound(tester, target);
    await tester.ensureVisible(target.first);
    await tester.tap(target.first);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilFound(tester, find.text('Unsaved changes'));

    final save = find.widgetWithText(FilledButton, 'Save');
    await pumpUntilFound(tester, save);
    await tester.tap(save.first);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntilFound(
      tester,
      find.textContaining('Settings saved'),
      timeout: const Duration(seconds: 15),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('ST-04 discard unsaved changes on leave', (tester) async {
    await seedMinimal(
      workspace: 'ST Discard',
      suffix: 'st-04',
      project: 'StDiscard',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ST Discard');
    await openSettings(tester);
    await pumpUntilFound(tester, find.text('Auto Save'));

    final switches = find.byType(Switch);
    await pumpUntilFound(tester, switches);
    await tester.ensureVisible(switches.first);
    await tester.tap(switches.first);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilFound(tester, find.text('Unsaved changes'));

    // Leave Settings via Explorer — triggers the unsaved-changes dialog.
    await tapSidebarPanel(tester, 'Explorer');
    await tester.pump(const Duration(milliseconds: 400));

    final discard = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Discard'),
    );
    await pumpUntilFound(tester, discard);
    await tester.tap(discard.first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Large Run Threshold'), findsNothing);
    expect(find.text('Unsaved changes'), findsNothing);

    harness.expectNoFlutterErrors();
  });
}
