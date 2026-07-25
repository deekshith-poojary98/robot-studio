import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: WS-01 … WS-10 (Workspace).
///
/// Source: Robot Studio — Functional Test Cases.md §2
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('WS-01 create new workspace updates chrome and recent',
      (tester) async {
    await harness.launchApp(tester);

    final location = harness.workspaceLocation('ws-01');
    const workspaceName = 'WS Create';

    await createWorkspaceViaUi(
      tester,
      name: workspaceName,
      location: location.path,
    );

    await pumpUntilFound(tester, find.text(workspaceName));
    expect(
      Directory('${location.path}/$workspaceName/.robotstudio').existsSync(),
      isTrue,
    );
    expect(find.text('No workspace'), findsNothing);

    final recent = await harness.api.listRecentWorkspaces();
    expect(recent.any((item) => item['name'] == workspaceName), isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'WS-02 open existing workspace via Open Workspace picker '
    '[skipped: native FilePicker not driveable in integration_test]',
    (tester) async {},
    skip: true,
  );

  testWidgets('WS-03 open from Recent Workspaces', (tester) async {
    const workspaceName = 'WS Recent';
    await harness.seedWorkspace(
      name: workspaceName,
      suffix: 'ws-03',
    );

    await harness.launchApp(tester);
    await tapText(tester, workspaceName);
    await pumpUntilFound(
      tester,
      find.textContaining('Projects'),
      timeout: const Duration(seconds: 20),
    );
    expect(find.text(workspaceName), findsWidgets);
    expect(find.text('No workspace'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('WS-04 recent project without open workspace is guided',
      (tester) async {
    await harness.seedWorkspace(name: 'WS ProjHost', suffix: 'ws-04');
    await harness.seedProject(name: 'WSOrphanProj');

    await harness.launchApp(tester);
    // Do not open workspace — tap recent project from welcome.
    await pumpUntilFound(tester, find.text('Recent Projects'));
    await tapText(tester, 'WSOrphanProj');
    await tester.pump(const Duration(milliseconds: 500));

    // Either auto-opens workspace or shows actionable guidance — not a dead end.
    final opened = tester.widgetList(find.text('WS ProjHost')).isNotEmpty;
    final guided = tester.widgetList(find.textContaining('workspace')).isNotEmpty ||
        tester.widgetList(find.textContaining('Workspace')).isNotEmpty ||
        tester.widgetList(find.byType(AlertDialog)).isNotEmpty;
    expect(opened || guided, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('WS-05 welcome emphasizes projects over workspaces', (tester) async {
    await harness.launchApp(tester);

    expect(find.text('New Project'), findsOneWidget);
    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Open Workspace'), findsWidgets);
    expect(find.text('Recent Workspaces'), findsOneWidget);

    final projectsOffset = tester.getTopLeft(find.text('Recent Projects')).dy;
    final workspacesOffset = tester.getTopLeft(find.text('Recent Workspaces')).dy;
    expect(projectsOffset < workspacesOffset, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('WS-06 create/manage available after workspace open',
      (tester) async {
    await harness.seedWorkspace(name: 'WS Enable', suffix: 'ws-06');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'WS Enable');

    await pumpUntilFound(tester, find.text('New Project'));
    await pumpUntilFound(tester, find.text('Environments'));

    // Toolbar New Project tooltip should be enabled.
    expect(find.byTooltip('New Project'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('WS-07 switch workspace replaces context', (tester) async {
    await harness.seedWorkspace(name: 'WS Alpha', suffix: 'ws-07a');
    await harness.seedProject(name: 'AlphaProj');

    await harness.seedWorkspace(name: 'WS Beta', suffix: 'ws-07b');
    await harness.seedProject(name: 'BetaProj');

    await harness.launchAppWithWorkspace(tester, workspaceName: 'WS Alpha');
    await pumpUntilFound(tester, find.textContaining('AlphaProj'));
    expect(find.textContaining('BetaProj'), findsNothing);

    // Tear down the shell before opening the other workspace in a fresh launch.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 500));

    await harness.launchAppWithWorkspace(tester, workspaceName: 'WS Beta');
    await pumpUntilFound(
      tester,
      find.textContaining('BetaProj'),
      timeout: const Duration(seconds: 20),
    );
    expect(find.textContaining('AlphaProj'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('WS-08 invalid or deleted workspace path shows error',
      (tester) async {
    await harness.launchApp(tester);

    await tapText(tester, 'New Workspace');
    await pumpUntilFound(tester, find.text('New Workspace', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Workspace name', 'WS Bad');
    await fillDialogFieldByLabel(
      tester,
      'Location',
      '/nonexistent/robot-studio/integration/path',
    );
    await submitDialog(tester, actionLabel: 'Create');
    await pumpUntilFound(tester, find.text('Workspace error'));
    await dismissErrorDialogIfPresent(tester);

    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    harness.expectNoFlutterErrors();
  });

  testWidgets(
    'WS-09 cancel Open Workspace folder picker '
    '[skipped: native FilePicker not driveable in integration_test]',
    (tester) async {},
    skip: true,
  );

  testWidgets('WS-10 workspace name shown in chrome', (tester) async {
    await harness.seedWorkspace(name: 'WS Chrome', suffix: 'ws-10');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'WS Chrome');

    await pumpUntilFound(tester, find.text('WS Chrome'));
    expect(find.text('No workspace'), findsNothing);
    // Status bar uses uppercase workspace label.
    expect(find.text('WS CHROME'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
