import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('create workspace updates explorer and recent list', (tester) async {
    await harness.launchApp(tester);

    final location = harness.workspaceLocation('flow-a');
    const workspaceName = 'Integration WS A';

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

    final recent = await harness.api.listRecentWorkspaces();
    expect(
      recent.any((item) => item['name'] == workspaceName),
      isTrue,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('reopen workspace from recent list', (tester) async {
    const workspaceName = 'Integration WS Reopen';
    await harness.seedWorkspace(
      name: workspaceName,
      suffix: 'reopen',
    );

    await harness.launchApp(tester);
    await tapText(tester, workspaceName);
    await pumpUntilFound(
      tester,
      find.textContaining('Projects'),
      timeout: const Duration(seconds: 15),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('invalid workspace location shows error', (tester) async {
    await harness.launchApp(tester);

    await tapText(tester, 'New Workspace');
    await pumpUntilFound(tester, find.text('New Workspace', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Workspace name', 'Bad WS');
    await fillDialogFieldByLabel(
      tester,
      'Location',
      '/nonexistent/robot-studio/integration/path',
    );
    await submitDialog(tester, actionLabel: 'Create');
    await pumpUntilFound(tester, find.text('Workspace error'));
    await dismissErrorDialogIfPresent(tester);

    harness.expectNoFlutterErrors();
  });
}
