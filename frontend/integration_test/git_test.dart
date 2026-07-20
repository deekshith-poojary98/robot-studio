import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('git init, commit, history, and branch checkout', (tester) async {
    final workspace = await harness.seedWorkspace(name: 'Git Flow WS', suffix: 'git');
    final workspacePath = workspace['path'] as String;
    await harness.seedEnvironment(name: 'git-env', installRobot: false);

    final project = await harness.seedProject(name: 'GitProject');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/git.robot';
    Directory('$projectPath/tests').createSync(recursive: true);
    File(suitePath).writeAsStringSync(
      '*** Test Cases ***\nGit\n    Log    one\n',
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Git Flow WS');
    await openSourceControl(tester);

    await tapText(tester, 'Initialize Git Repository');
    await pumpUntilAbsent(
      tester,
      find.text('Not a Git repository'),
      timeout: const Duration(seconds: 30),
    );
    await harness.configureGitIdentityAfterInit(workspacePath);

    await harness.api.writeFile(
      path: suitePath,
      content: '*** Test Cases ***\nGit\n    Log    changed\n',
    );
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, find.text('Untracked'));

    final commitField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Describe your changes…',
    );
    await tester.enterText(commitField, 'Integration commit');
    await tapText(tester, 'Commit All');
    await pumpUntilFound(tester, find.text('No changes'), timeout: const Duration(seconds: 30));

    final history = await harness.api.gitHistory();
    expect(history, isNotEmpty);

    await harness.api.gitCreateBranch('feature/it-branch');
    final status = await harness.api.gitCheckout('feature/it-branch');
    expect(status['branch'], 'feature/it-branch');

    harness.expectNoFlutterErrors();
  });
}
