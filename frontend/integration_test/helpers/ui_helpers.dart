import 'package:flutter/material.dart';
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
  // Connection chrome is hidden; wait for welcome actions that need a live API.
  await pumpUntilFound(tester, find.text('Open Project'), timeout: timeout);
  expect(find.text('CONNECTED'), findsNothing);
  expect(find.text('OFFLINE'), findsNothing);
}

Future<void> waitForWelcomeScreen(WidgetTester tester) async {
  await pumpUntilFound(tester, find.text('Robot Studio'));
  await pumpUntilFound(tester, find.text('Recent Workspaces'));
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
  final checkbox = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(CheckboxListTile),
  );
  await pumpUntilFound(tester, checkbox);
  final tile = tester.widget<CheckboxListTile>(checkbox.first);
  if ((tile.value ?? false) != enabled) {
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
    await tester.tap(ok.first);
    await tester.pump();
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
  await tapTooltip(tester, 'New Project');
  await pumpUntilFound(tester, find.text('New Project', skipOffstage: false));
  await fillDialogFieldByLabel(tester, 'Project name', name);
  await submitDialog(tester, actionLabel: 'Create');
  await pumpUntilAbsent(tester, find.text('New Project'));
}

Future<void> refreshEnvironmentsInUi(WidgetTester tester) async {
  await openEnvironmentManager(tester);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> openEnvironmentManager(WidgetTester tester) async {
  final tooltip = find.byTooltip('Manage Environments');
  if (tester.widgetList(tooltip).isNotEmpty) {
    await tapTooltip(tester, 'Manage Environments');
  } else {
    await tapText(tester, 'Manage Environments…');
  }
  await pumpUntilFound(tester, find.text('Environment Manager'));
}

Future<void> openPackageManager(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Packages');
  await pumpUntilFound(tester, find.text('Package Manager'));
}

Future<void> openSourceControl(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Source Control');
  await pumpUntilFound(tester, find.text('Source Control'));
}

Future<void> openPluginManager(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Plugins');
  await pumpUntilFound(tester, find.text('Plugin Manager'));
}

Future<void> openReports(WidgetTester tester) async {
  await tapSidebarPanel(tester, 'Reports');
  await pumpUntilFound(tester, find.text('Reports'));
}

Future<void> tapToolbarAction(WidgetTester tester, String label) async {
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
  await tester.tap(
    find.textContaining('Search commands, files, symbols').first,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilFound(
    tester,
    find.textContaining('Type a command, file, or symbol'),
  );
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
  await tapSidebarPanel(tester, 'Explorer');
  await scrollToAndTap(tester, find.text(projectName));
  // ProjectDetailsPanel renders labels uppercased (e.g. TYPE, LOCATION).
  await pumpUntilFound(tester, find.text('TYPE'));
}

Future<void> openRobotFileInExplorer(
  WidgetTester tester,
  String fileName, {
  String? projectName,
}) async {
  await tapSidebarPanel(tester, 'Explorer');

  final fileFinder = find.text(fileName);
  if (tester.widgetList(fileFinder).isEmpty) {
    if (projectName != null) {
      final projectLabels = find.text(projectName);
      await pumpUntilFound(
        tester,
        projectLabels,
        timeout: const Duration(seconds: 20),
      );
      // Expand both the Projects tile and the Files-tree directory node.
      final count = tester.widgetList(projectLabels).length;
      for (var i = 0; i < count; i++) {
        await tester.ensureVisible(projectLabels.at(i));
        await tester.tap(projectLabels.at(i));
        await tester.pump(const Duration(milliseconds: 300));
        if (tester.widgetList(fileFinder).isNotEmpty) break;
      }
    }

    final testsFolders = find.text('tests');
    final testsCount = tester.widgetList(testsFolders).length;
    for (var i = 0; i < testsCount; i++) {
      await tester.ensureVisible(testsFolders.at(i));
      await tester.tap(testsFolders.at(i));
      await tester.pump(const Duration(milliseconds: 300));
      if (tester.widgetList(fileFinder).isNotEmpty) break;
    }

    final resourceFolders = find.text('resources');
    final resourceCount = tester.widgetList(resourceFolders).length;
    for (var i = 0; i < resourceCount; i++) {
      await tester.ensureVisible(resourceFolders.at(i));
      await tester.tap(resourceFolders.at(i));
      await tester.pump(const Duration(milliseconds: 300));
      if (tester.widgetList(fileFinder).isNotEmpty) break;
    }
  }

  await scrollToAndTap(tester, fileFinder);
}

/// Waits until the editor page is mounted (tabs / breadcrumb / code area).
Future<void> waitForEditorOpen(WidgetTester tester) async {
  await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
}

/// Opens the command palette and runs the first item whose title matches [title].
Future<void> runCommandPaletteAction(WidgetTester tester, String title) async {
  await pumpUntilFound(tester, find.text('Search commands, files, symbols…'));
  await tester.tap(find.text('Search commands, files, symbols…'));
  await tester.pumpAndSettle();
  final field = find.byType(TextField).last;
  await tester.enterText(field, title);
  await tester.pumpAndSettle();
  final item = find.text(title);
  await pumpUntilFound(tester, item);
  await tester.tap(item.first);
  await tester.pumpAndSettle();
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
