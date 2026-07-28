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

  testWidgets('create project updates explorer and recent projects', (tester) async {
    await harness.seedWorkspace(name: 'Project Flow WS', suffix: 'create-project');
    await harness.seedEnvironment(name: 'project-flow-env');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'Project Flow WS');

    const projectName = 'Integration Project';
    await createProjectViaUi(tester, name: projectName);

    await pumpUntilFound(tester, find.text(projectName));
    final projects = await harness.api.listProjects();
    expect(projects.any((item) => item['name'] == projectName), isTrue);

    final recent = await harness.api.listRecentProjects();
    expect(recent.any((item) => item['name'] == projectName), isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('import project displays project details', (tester) async {
    await harness.seedWorkspace(name: 'Import Flow WS', suffix: 'import-project');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'Import Flow WS');

    final importRoot = harness.resources.scratch('import-me');
    importRoot.createSync(recursive: true);
    Directory('${importRoot.path}/tests').createSync(recursive: true);
    File('${importRoot.path}/tests/sample.robot').writeAsStringSync(
      '*** Test Cases ***\nSample\n    Log    x\n',
    );

    await tapTooltip(tester, 'Import Project');
    await pumpUntilFound(tester, find.text('Import Project', skipOffstage: false));
    await fillDialogFieldByLabel(tester, 'Project path', importRoot.path);
    await submitDialog(tester, actionLabel: 'Import');
    await pumpUntilAbsent(tester, find.text('Import Project'));

    await pumpUntilFound(tester, find.text('import-me'));
    expect(find.textContaining('Imported'), findsNothing);
    expect(find.text('LOCATION'), findsOneWidget);
    harness.expectNoFlutterErrors();
  });
}
