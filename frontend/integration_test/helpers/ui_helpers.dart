import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [finder] matches at least [minHits] widgets.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  int minHits = 1,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.widgetList(finder).length >= minHits) {
      await tester.pump(const Duration(milliseconds: 100));
      return;
    }
  }
  throw TestFailure(
    'Timed out waiting for '
    '${finder.describeMatch(minHits == 1 ? Plurality.one : Plurality.many)} '
    '(expected >= $minHits)',
  );
}

/// Waits until [finder] no longer matches any widgets.
Future<void> pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.widgetList(finder).isEmpty) {
      return;
    }
  }
  throw TestFailure(
    'Timed out waiting for absence of ${finder.describeMatch(Plurality.zero)}',
  );
}

Future<void> waitForBackendReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  // Connection chrome is hidden. Ready means welcome actions OR session chrome.
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    final welcome = tester.widgetList(find.text('Open Project')).isNotEmpty ||
        tester.widgetList(find.byKey(const Key('welcome.wordmark'))).isNotEmpty;
    final session =
        tester.widgetList(find.byKey(const Key('toolbar.search'))).isNotEmpty;
    if (welcome || session) {
      expect(find.text('CONNECTED'), findsNothing);
      expect(find.text('OFFLINE'), findsNothing);
      return;
    }
  }
  throw TestFailure(
    'Timed out waiting for app shell (welcome or toolbar) after backend connect',
  );
}

/// Saves the active editor via the command palette (no Save toolbar label).
Future<void> saveActiveEditor(WidgetTester tester) async {
  await runCommandPaletteAction(tester, 'Save File');
}

Future<void> waitForWelcomeScreen(WidgetTester tester) async {
  // Branding is a wordmark image (semanticLabel only), not Text('Robot Studio').
  await pumpUntilFound(tester, find.byKey(const Key('welcome.wordmark')));
  await pumpUntilFound(tester, find.text('Recent Projects'));
  await pumpUntilFound(tester, find.text('Open Project'));
}

Future<void> tapText(
  WidgetTester tester,
  String text, {
  bool warnIfMissed = false,
}) async {
  final finder = find.text(text);
  await pumpUntilFound(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> tapTooltip(WidgetTester tester, String message) async {
  final finder = find.byTooltip(message);
  await pumpUntilFound(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> tapSidebarPanel(WidgetTester tester, String label) async {
  final exact = find.byTooltip(label);
  if (tester.widgetList(exact).isNotEmpty) {
    await tester.tap(exact.first);
    await tester.pump();
    return;
  }

  // Activity rail tooltips are descriptive: "Reports — run history…".
  final descriptive = find.byWidgetPredicate(
    (widget) =>
        widget is Tooltip &&
        widget.message != null &&
        (widget.message!.startsWith('$label —') ||
            widget.message!.startsWith('$label -') ||
            widget.message == label),
  );
  await pumpUntilFound(tester, descriptive);
  await tester.tap(descriptive.first);
  await tester.pump();
}

Finder _dialogField(String labelText) {
  final dialog = find.byType(AlertDialog);
  return find.descendant(
    of: dialog,
    matching: find.widgetWithText(TextField, labelText),
  );
}

Future<void> fillDialogFieldByLabel(
  WidgetTester tester,
  String labelText,
  String value,
) async {
  final field = _dialogField(labelText);
  await pumpUntilFound(tester, field);
  await tester.enterText(field.first, value);
  await tester.pump();
}

Future<void> waitForDialogInterpreterLoad(WidgetTester tester) async {
  final loadingInDialog = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(CircularProgressIndicator),
  );
  if (tester.widgetList(loadingInDialog).isNotEmpty) {
    await pumpUntilAbsent(
      tester,
      loadingInDialog,
      timeout: const Duration(seconds: 30),
    );
  }
}

Future<void> fillPythonInterpreterField(
  WidgetTester tester,
  String pythonPath,
) async {
  final dialog = find.byType(AlertDialog);
  final pythonField = find.descendant(
    of: dialog,
    matching: find.widgetWithText(TextField, 'Python interpreter'),
  );
  await pumpUntilFound(tester, pythonField);

  final fieldWidget = tester.widget<TextField>(pythonField.first);
  if (fieldWidget.enabled == false) {
    final dropdown = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.tap(dropdown);
    await pumpUntilFound(tester, find.text('Custom path…'));
    await tester.tap(find.text('Custom path…').last);
    await tester.pump();
    await pumpUntilFound(tester, pythonField);
  }

  await fillDialogFieldByLabel(tester, 'Python interpreter', pythonPath);
}

Future<void> setInstallRobotFramework(
  WidgetTester tester, {
  required bool enabled,
}) async {
  final dialog = find.byType(AlertDialog);
  await pumpUntilFound(tester, dialog);
  final label = find.descendant(
    of: dialog,
    matching: find.text('Install Robot Framework'),
  );
  await pumpUntilFound(tester, label);
  final checkbox = find.descendant(
    of: dialog,
    matching: find.byType(Checkbox),
  );
  await pumpUntilFound(tester, checkbox);
  final box = tester.widget<Checkbox>(checkbox.first);
  if ((box.value ?? false) != enabled) {
    await tester.tap(checkbox.first);
    await tester.pump();
  }
}

Future<void> createEnvironmentViaUi(
  WidgetTester tester, {
  required String name,
  String? pythonInterpreter,
  bool installRobot = false,
}) async {
  await openEnvironmentManager(tester);
  await tapText(tester, 'Create');
  await pumpUntilFound(
    tester,
    find.text('Create Environment', skipOffstage: false),
  );
  await waitForDialogInterpreterLoad(tester);

  await fillDialogFieldByLabel(tester, 'Environment name', name);

  if (pythonInterpreter != null) {
    await fillPythonInterpreterField(tester, pythonInterpreter);
  }

  await setInstallRobotFramework(tester, enabled: installRobot);
  await submitDialog(tester, actionLabel: 'Create');
  await pumpUntilAbsent(
    tester,
    find.text('Create Environment'),
    timeout: const Duration(minutes: 3),
  );
}

Future<void> submitDialog(
  WidgetTester tester, {
  String actionLabel = 'Create',
}) async {
  final dialog = find.byType(AlertDialog);
  await pumpUntilFound(tester, dialog);

  final filled = find.descendant(
    of: dialog,
    matching: find.widgetWithText(FilledButton, actionLabel),
  );
  if (tester.widgetList(filled).isNotEmpty) {
    await tester.tap(filled.last);
    await tester.pump();
    return;
  }

  final textButton = find.descendant(
    of: dialog,
    matching: find.widgetWithText(TextButton, actionLabel),
  );
  await pumpUntilFound(tester, textButton);
  await tester.tap(textButton.last);
  await tester.pump();
}

Future<void> dismissErrorDialogIfPresent(WidgetTester tester) async {
  final ok = find.text('OK');
  if (tester.widgetList(ok).isNotEmpty) {
    await tester.tap(ok.first, warnIfMissed: false);
    await tester.pump();
  }
}

/// Clears modal barriers (dialogs / palette) that absorb explorer taps.
Future<void> dismissModalOverlays(WidgetTester tester) async {
  await dismissErrorDialogIfPresent(tester);
  for (var i = 0; i < 3; i++) {
    if (tester.widgetList(find.byType(Dialog)).isEmpty &&
        tester.widgetList(find.byType(ModalBarrier)).isEmpty) {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 250));
    await dismissErrorDialogIfPresent(tester);
  }
}

Future<void> createWorkspaceViaUi(
  WidgetTester tester, {
  required String name,
  required String location,
}) async {
  await tapText(tester, 'New Workspace');
  await pumpUntilFound(tester, find.text('New Workspace', skipOffstage: false));
  await fillDialogFieldByLabel(tester, 'Workspace name', name);
  await fillDialogFieldByLabel(tester, 'Location', location);
  await submitDialog(tester, actionLabel: 'Create');
  await pumpUntilAbsent(tester, find.text('New Workspace'));
}

Future<void> createProjectViaUi(
  WidgetTester tester, {
  required String name,
}) async {
  // New Project lives in the project chip popup (not a bare tooltip).
  final chip = find.byKey(const Key('toolbar.project'));
  await pumpUntilFound(tester, chip);
  await tester.tap(chip);
  await tester.pump(const Duration(milliseconds: 250));
  await pumpUntilFound(tester, find.text('New Project'));
  await tester.tap(find.text('New Project').last);
  await tester.pump(const Duration(milliseconds: 500));
  await fillDialogFieldByLabel(tester, 'Project name', name);
  await submitDialog(tester, actionLabel: 'Create');
  await pumpUntilAbsent(
    tester,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('New Project'),
    ),
  );
}

Future<void> refreshEnvironmentsInUi(WidgetTester tester) async {
  await openEnvironmentManager(tester);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> openEnvironmentManager(WidgetTester tester) async {
  // Env actions live in the toolbar chip popup (not a bare tooltip).
  final chip = find.byKey(const Key('toolbar.environment'));
  await pumpUntilFound(tester, chip);
  await tester.tap(chip);
  await tester.pump(const Duration(milliseconds: 200));
  await pumpUntilFound(tester, find.text('Manage Environments…'));
  await tester.tap(find.text('Manage Environments…').last);
  await tester.pump();
  await pumpUntilFound(tester, find.text('Environment Manager'));
}

Future<void> openPackageManager(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Packages');
  await pumpUntilFound(tester, find.text('Package Manager'));
}

Future<void> openSourceControl(
  WidgetTester tester, {
  String? projectName,
}) async {
  if (projectName != null) {
    await openProjectInExplorer(tester, projectName: projectName);
  }
  await tapSidebarPanel(tester, 'Source Control');
  await pumpUntilFound(tester, find.text('Source Control'));
}

Future<void> openPluginManager(WidgetTester tester) async {
  // Beta: Plugins is hidden from the activity bar and command palette.
  // Re-enable when showInActivityBar is true and the plugins.open palette
  // entry is restored in app_shell.dart.
  throw TestFailure(
    'Plugin Manager UI is hidden for beta '
    '(no activity-bar button or command-palette entry).',
  );
}

Future<void> openReports(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Reports');
  await pumpUntilFound(tester, find.text('Reports'));
}

Future<void> tapToolbarAction(WidgetTester tester, String label) async {
  // Prefer stable keys — tooltips change with enabled/disabled/env state.
  if (label == 'Run' || label == 'Run current file') {
    final run = find.byKey(const Key('toolbar.run'));
    await pumpUntilFound(tester, run);
    await tester.tap(run);
    await tester.pump();
    return;
  }
  if (label == 'Run Project' ||
      label == 'Project' ||
      label == 'Run the selected project' ||
      label == 'Run the whole project') {
    final run = find.byKey(const Key('toolbar.run-project'));
    await pumpUntilFound(tester, run);
    await tester.tap(run);
    await tester.pump();
    return;
  }
  await tapTooltip(tester, label);
}

Future<void> openBottomTab(WidgetTester tester, String label) async {
  final expand = find.byIcon(Icons.keyboard_arrow_up);
  if (tester.widgetList(expand).isNotEmpty) {
    await tester.tap(expand.first);
    await tester.pump();
  }
  final tabLabel = label.toUpperCase();
  final tab = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        widget.data!.toUpperCase().startsWith(tabLabel),
  );
  await pumpUntilFound(tester, tab);
  await tester.tap(tab.first);
  await tester.pump();
}

Future<void> openCommandPalette(WidgetTester tester) async {
  // Hint text is InputDecoration only — wait for the dialog field instead.
  final field = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  // Reuse an already-open palette (e.g. prior action left the modal up, or
  // a missed toolbar tap left the barrier covering toolbar.search).
  if (tester.widgetList(field).isNotEmpty) {
    return;
  }
  final search = find.byKey(const Key('toolbar.search'));
  await pumpUntilFound(tester, search);
  await tester.tap(search, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 400));
  if (tester.widgetList(field).isEmpty) {
    // Retry once — modal barriers / overlays can absorb the first tap.
    await tester.tap(search, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await pumpUntilFound(tester, field);
}

Future<void> scrollToAndTap(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  await pumpUntilFound(tester, finder);
  final scrollTarget =
      scrollable ??
      find.descendant(
        of: find.byKey(const Key('workspace-explorer-list')),
        matching: find.byType(Scrollable),
      );
  if (tester.widgetList(scrollTarget).isNotEmpty) {
    await tester.scrollUntilVisible(finder.first, 80, scrollable: scrollTarget);
  } else {
    await tester.ensureVisible(finder.first);
  }
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(tester.getCenter(finder.first));
  await tester.pump();
}

Future<void> openProjectInExplorer(
  WidgetTester tester, {
  required String projectName,
}) async {
  await dismissModalOverlays(tester);
  await tapSidebarPanel(tester, 'Explorer');
  final explorer = find.byKey(const Key('workspace-explorer-list'));
  final projectInTree = find.descendant(
    of: explorer,
    matching: find.text(projectName),
  );
  await scrollToAndTap(
    tester,
    tester.widgetList(projectInTree).isNotEmpty
        ? projectInTree
        : find.text(projectName),
  );
  // Editor start page (same view for project open / no file).
  await pumpUntilFound(tester, find.text('Start'));
}

Future<void> openRobotFileInExplorer(
  WidgetTester tester,
  String fileName, {
  String? projectName,
}) async {
  await dismissModalOverlays(tester);
  await tapSidebarPanel(tester, 'Explorer');

  final explorer = find.byKey(const Key('workspace-explorer-list'));
  Finder scoped(String text) {
    final inTree = find.descendant(of: explorer, matching: find.text(text));
    return tester.widgetList(inTree).isNotEmpty ? inTree : find.text(text);
  }

  final fileFinder = scoped(fileName);
  if (tester.widgetList(fileFinder).isEmpty) {
    if (projectName != null) {
      final projectLabels = scoped(projectName);
      await pumpUntilFound(
        tester,
        projectLabels,
        timeout: const Duration(seconds: 20),
      );
      // Re-query each pass — expand/collapse mutates the tree.
      final count = tester.widgetList(projectLabels).length;
      for (var i = 0; i < count; i++) {
        final labels = scoped(projectName);
        if (i >= tester.widgetList(labels).length) break;
        await tester.ensureVisible(labels.at(i));
        await tester.tap(labels.at(i), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        if (tester.widgetList(scoped(fileName)).isNotEmpty) break;
      }
    }

    Future<void> expandFolder(String name) async {
      final folders = scoped(name);
      final count = tester.widgetList(folders).length;
      for (var i = 0; i < count; i++) {
        final current = scoped(name);
        if (i >= tester.widgetList(current).length) break;
        await tester.ensureVisible(current.at(i));
        await tester.tap(current.at(i), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        if (tester.widgetList(scoped(fileName)).isNotEmpty) return;
      }
    }

    await expandFolder('tests');
    if (tester.widgetList(scoped(fileName)).isEmpty) {
      await expandFolder('resources');
    }
  }

  await scrollToAndTap(tester, scoped(fileName));
}

/// Waits until the editor page is mounted (tabs / breadcrumb / code area).
Future<void> waitForEditorOpen(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
}

/// Opens the command palette and runs the first item whose title matches [title].
Future<void> runCommandPaletteAction(WidgetTester tester, String title) async {
  await openCommandPalette(tester);
  final field = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await pumpUntilFound(tester, field);
  await tester.enterText(field.first, title);
  await tester.pump(const Duration(milliseconds: 300));
  // Prefer a ListTile title over the TextField's own value (same string).
  final listItem = find.descendant(
    of: find.byType(ListTile),
    matching: find.text(title),
  );
  await pumpUntilFound(tester, listItem);
  await tester.tap(listItem.first);
  await tester.pump(const Duration(milliseconds: 400));
  // Wait for the modal to dismiss so the next toolbar.search tap can hit.
  await pumpUntilAbsent(tester, field, timeout: const Duration(seconds: 10));
}

/// Language / edit actions live on the window menu bar; E2E drives them via
/// the command palette (same handlers).
Future<void> tapEditorMenuAction(WidgetTester tester, String action) async {
  final title = switch (action) {
    'replace' => 'Replace',
    'format-selection' => 'Format Selection',
    'definition' => 'Go to Definition',
    'peek' => 'Peek Definition',
    'references' => 'Find References',
    'hover' => 'Show Hover Info',
    'open-symbol' => 'Go to Symbol in File…',
    'project-symbol' => 'Find Symbol in Project…',
    'reveal' => 'Reveal in Finder',
    _ => throw ArgumentError('Unknown editor menu action: $action'),
  };
  await runCommandPaletteAction(tester, title);
}

Future<void> tapEditorFormat(WidgetTester tester) async {
  await runCommandPaletteAction(tester, 'Format Document');
}

Future<void> tapEditorFind(WidgetTester tester) async {
  await runCommandPaletteAction(tester, 'Find');
}
