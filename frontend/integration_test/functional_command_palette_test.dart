import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/editor/editor_tabs_bar.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: CP-01 … CP-07 (Command palette).
///
/// Source: docs/internal/functional-test-cases.md §10
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  const suiteContent = '''*** Keywords ***
CpHello
    Log    hi

*** Test Cases ***
Cp Case
    CpHello
''';

  Future<void> seedPaletteWorkspace({
    required String workspace,
    required String suffix,
    required String project,
    String suiteFile = 'cp_suite.robot',
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: true);
    final created = await harness.seedProject(name: project);
    await harness.api.writeFile(
      path: '${created['path']}/tests/$suiteFile',
      content: suiteContent,
    );
    await harness.api.rebuildIndex();
  }

  Finder paletteField() => find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );

  testWidgets('CP-01 open palette via keyboard shortcut', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Keys',
      suffix: 'cp-01',
      project: 'CpKeys',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Keys');
    await waitForBackendReady(tester);

    // Meta/Ctrl key simulation trips HardwareKeyboard assertions under
    // integration_test. Assert the shell binds ⌘K/Ctrl+K, then open via the
    // same palette entry used by that shortcut.
    final shortcutsFinder = find.byType(Shortcuts);
    await pumpUntilFound(tester, shortcutsFinder);
    final shortcuts = tester.widgetList<Shortcuts>(shortcutsFinder);
    final bindsPalette = shortcuts.any(
      (widget) => widget.shortcuts.keys.any((activator) {
        return activator is SingleActivator &&
            activator.trigger == LogicalKeyboardKey.keyK &&
            (activator.meta || activator.control);
      }),
    );
    expect(bindsPalette, isTrue);

    await openCommandPalette(tester);
    expect(find.byType(Dialog), findsWidgets);
    expect(paletteField(), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-02 open palette via toolbar search chrome', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Chrome',
      suffix: 'cp-02',
      project: 'CpChrome',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Chrome');
    await openCommandPalette(tester);

    expect(find.textContaining('Type a command, file, or symbol'), findsOneWidget);
    expect(find.text('Index Status'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-03 filter commands', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Filter',
      suffix: 'cp-03',
      project: 'CpFilter',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Filter');
    await openCommandPalette(tester);

    await tester.enterText(paletteField(), 'env');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Manage Environments'), findsWidgets);
    expect(find.text('New Workspace'), findsNothing);

    await tester.enterText(paletteField(), 'report');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Open Reports'), findsWidgets);
    expect(find.text('Manage Environments'), findsNothing);

    await tester.enterText(paletteField(), 'run');
    await tester.pump(const Duration(milliseconds: 300));
    // Run commands require a selected project; "rebuild" is always available
    // once a workspace is open and still exercises filtering.
    await tester.enterText(paletteField(), 'rebuild');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Rebuild Index'), findsWidgets);
    expect(find.text('Manage Environments'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-04 activate command closes palette', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Activate',
      suffix: 'cp-04',
      project: 'CpActivate',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Activate');
    await openCommandPalette(tester);

    await tester.enterText(paletteField(), 'Manage Environments');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Manage Environments').last);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntilAbsent(
      tester,
      find.textContaining('Type a command, file, or symbol'),
    );
    await pumpUntilFound(tester, find.text('Environment Manager'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-05 file search opens editor', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP File',
      suffix: 'cp-05',
      project: 'CpFile',
      suiteFile: 'cp05_unique.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP File');
    await openCommandPalette(tester);

    await tester.enterText(paletteField(), 'cp05_unique.robot');
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntilFound(
      tester,
      find.text('cp05_unique.robot'),
      timeout: const Duration(seconds: 20),
    );
    expect(find.textContaining('site-packages'), findsNothing);

    await tester.tap(find.text('cp05_unique.robot').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tapSidebarPanel(tester, 'Explorer');
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(EditorTabsBar),
        matching: find.text('cp05_unique.robot'),
      ),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-06 symbol search in palette', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Symbol',
      suffix: 'cp-06',
      project: 'CpSymbol',
      suiteFile: 'cp06_symbol.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Symbol');
    await openCommandPalette(tester);

    await tester.enterText(paletteField(), 'CpHello');
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(
      tester,
      find.textContaining('CpHello'),
      timeout: const Duration(seconds: 30),
    );

    await tester.tap(find.textContaining('CpHello').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tapSidebarPanel(tester, 'Explorer');
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(EditorTabsBar),
        matching: find.text('cp06_symbol.robot'),
      ),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('CP-07 Esc closes palette', (tester) async {
    await seedPaletteWorkspace(
      workspace: 'CP Esc',
      suffix: 'cp-07',
      project: 'CpEsc',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'CP Esc');
    await openCommandPalette(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilAbsent(
      tester,
      find.textContaining('Type a command, file, or symbol'),
    );
    expect(find.text('NO PROJECT'), findsNothing);

    harness.expectNoFlutterErrors();
  });
}
