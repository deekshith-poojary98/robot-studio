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

  testWidgets('language features update editor and problems panel', (tester) async {
    await harness.seedWorkspace(name: 'Language Flow WS', suffix: 'language');
    await harness.seedEnvironment(name: 'language-env', installRobot: false);

    final project = await harness.seedProject(name: 'LanguageProject');
    final projectPath = project['path'] as String;
    final suitePath = '$projectPath/tests/language.robot';
    Directory('$projectPath/tests').createSync(recursive: true);
    const broken = '*** Test Cases ***\nBroken\n    UnknownKeyword    x\n';
    File(suitePath).writeAsStringSync(broken);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Language Flow WS');
    await openRobotFileInExplorer(tester, 'language.robot');
    await pumpUntilFound(tester, find.byKey(const Key('editor.format')));

    final diagnostics = await harness.api.languageDiagnostics(
      filePath: suitePath,
      content: broken,
    );
    expect(diagnostics['diagnostics'], isA<List<dynamic>>());

    final formatted = await harness.api.languageFormat(
      filePath: suitePath,
      content: broken,
    );
    expect(formatted['content'], isNotEmpty);

    await tapText(tester, 'Format');
    await tester.pump(const Duration(milliseconds: 500));

    await openBottomTab(tester, 'Problems');
    await pumpUntilFound(tester, find.textContaining('UnknownKeyword'));

    expect(find.byKey(const Key('editor.definition')), findsOneWidget);
    expect(find.byKey(const Key('editor.find')), findsOneWidget);

    harness.expectNoFlutterErrors();
  });
}
