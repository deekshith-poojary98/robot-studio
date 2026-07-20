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

  testWidgets('open, edit, save, and reopen robot file with tabs', (tester) async {
    await harness.seedWorkspace(name: 'Editor Flow WS', suffix: 'editor');
    await harness.seedEnvironment(name: 'editor-env', installRobot: false);

    final project = await harness.seedProject(name: 'EditorProject');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/sample.robot';
    Directory('$projectPath/tests').createSync(recursive: true);
    File(suitePath).writeAsStringSync(
      '*** Test Cases ***\nSample\n    Log    original\n',
    );
    File('$projectPath/tests/second.robot').writeAsStringSync(
      '*** Test Cases ***\nSecond\n    Log    two\n',
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Editor Flow WS');

    await openRobotFileInExplorer(tester, 'sample.robot');
    await pumpUntilFound(tester, find.byKey(const Key('editor.format')));

    await tapText(tester, 'Format');
    await tester.pump(const Duration(milliseconds: 500));

    await tapText(tester, 'Save');
    await tester.pump(const Duration(milliseconds: 500));

    final persisted = await harness.api.readFile(suitePath);
    expect(persisted['content'], contains('Sample'));
    expect(persisted['content'], contains('Log'));

    await scrollToAndTap(tester, find.text('second.robot'));
    await pumpUntilFound(tester, find.text('Second'));

    expect(find.text('sample.robot'), findsWidgets);
    expect(find.text('second.robot'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
