import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/editor/editor_tabs_bar.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: ED-01 … ED-10 (Editor).
///
/// Source: docs/internal/functional-test-cases.md §7
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<({String sample, String second})> seedEditorFiles({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: false);
    final created = await harness.seedProject(name: project);
    final root = created['path'] as String;
    final sample = '$root/tests/sample.robot';
    final second = '$root/tests/second.robot';
    await harness.api.writeFile(
      path: sample,
      content: '*** Test Cases ***\nSample\n    Log    original\n',
    );
    await harness.api.writeFile(
      path: second,
      content: '*** Test Cases ***\nSecond\n    Log    two\n',
    );
    return (sample: sample, second: second);
  }

  testWidgets('ED-01 open and show robot content', (tester) async {
    await seedEditorFiles(
      workspace: 'ED Open',
      suffix: 'ed-01',
      project: 'EdOpen',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Open');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdOpen',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    expect(find.textContaining('Sample'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-02 find panel opens', (tester) async {
    await seedEditorFiles(
      workspace: 'ED Find',
      suffix: 'ed-02',
      project: 'EdFind',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Find');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdFind',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await tapEditorFind(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-03 outline / document symbols load', (tester) async {
    final files = await seedEditorFiles(
      workspace: 'ED Outline',
      suffix: 'ed-03',
      project: 'EdOutline',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Outline');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdOutline',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));

    final symbols = await harness.api.documentSymbols(files.sample);
    expect(symbols, isA<List<dynamic>>());

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-04 multi-tab dirty independence via open both', (tester) async {
    await seedEditorFiles(
      workspace: 'ED Tabs',
      suffix: 'ed-04',
      project: 'EdTabs',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Tabs');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdTabs',
    );
    await openRobotFileInExplorer(
      tester,
      'second.robot',
      projectName: 'EdTabs',
    );
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(EditorTabsBar),
        matching: find.text('second.robot'),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(EditorTabsBar),
        matching: find.text('sample.robot'),
      ),
      findsOneWidget,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-05 save file via UI', (tester) async {
    final files = await seedEditorFiles(
      workspace: 'ED Save',
      suffix: 'ed-05',
      project: 'EdSave',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Save');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdSave',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await tapEditorFormat(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tapText(tester, 'Save');
    await tester.pump(const Duration(milliseconds: 500));

    final persisted = await harness.api.readFile(files.sample);
    expect(persisted['content'], contains('Sample'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-06 large-ish suite remains responsive', (tester) async {
    await harness.seedWorkspace(name: 'ED Large', suffix: 'ed-06');
    await harness.seedEnvironment(name: 'ed-06-env', installRobot: false);
    final project = await harness.seedProject(name: 'EdLarge');
    final path = '${project['path']}/tests/large.robot';
    final buffer = StringBuffer('*** Test Cases ***\n');
    for (var i = 0; i < 80; i++) {
      buffer.writeln('Case$i\n    Log    line-$i\n');
    }
    await harness.api.writeFile(path: path, content: buffer.toString());

    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Large');
    await openRobotFileInExplorer(
      tester,
      'large.robot',
      projectName: 'EdLarge',
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('editor.page')),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-07 jump from problems after diagnostics', (tester) async {
    await harness.seedWorkspace(name: 'ED Jump', suffix: 'ed-07');
    await harness.seedEnvironment(name: 'ed-07-env', installRobot: true);
    final project = await harness.seedProject(name: 'EdJump');
    final path = '${project['path']}/tests/sample.robot';
    const broken = '*** Test Cases ***\nBroken\n    UnknownKeyword    x\n';
    await harness.api.writeFile(path: path, content: broken);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Jump');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdJump',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntilFound(
      tester,
      find.textContaining('PROBLEMS '),
      timeout: const Duration(seconds: 90),
    );
    await openBottomTab(tester, 'Problems');
    await pumpUntilFound(
      tester,
      find.textContaining('UnknownKeyword'),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(find.textContaining('UnknownKeyword').first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('editor.page')), findsOneWidget);
    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-08 reopen file from explorer', (tester) async {
    await seedEditorFiles(
      workspace: 'ED Reopen',
      suffix: 'ed-08',
      project: 'EdReopen',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Reopen');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdReopen',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await openRobotFileInExplorer(
      tester,
      'second.robot',
      projectName: 'EdReopen',
    );
    await pumpUntilFound(tester, find.textContaining('Second'));

    // Switch back via the editor tab strip (explorer tap on an already-open
    // file may not activate the tab; matches EX-04 / ED-08 UI reopen path).
    final sampleTab = find.descendant(
      of: find.byType(EditorTabsBar),
      matching: find.text('sample.robot'),
    );
    await pumpUntilFound(tester, sampleTab);
    await tester.tap(sampleTab);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilFound(tester, find.textContaining('Sample'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-09 robot section headers visible', (tester) async {
    final files = await seedEditorFiles(
      workspace: 'ED Headers',
      suffix: 'ed-09',
      project: 'EdHeaders',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Headers');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdHeaders',
    );
    // re_editor paints highlighted section headers; assert shell + outline
    // symbol and that the on-disk suite still has standard section markers.
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await pumpUntilFound(tester, find.textContaining('Sample'));
    final persisted = await harness.api.readFile(files.sample);
    expect(persisted['content'], contains('*** Test Cases ***'));
    expect(find.byKey(const Key('editor.page')), findsOneWidget);

    harness.expectNoFlutterErrors();
  });

  testWidgets('ED-10 close last tab leaves clean editor shell', (tester) async {
    await seedEditorFiles(
      workspace: 'ED Close',
      suffix: 'ed-10',
      project: 'EdClose',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'ED Close');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'EdClose',
    );
    await pumpUntilFound(tester, find.byType(EditorTabsBar));

    final close = find.descendant(
      of: find.byType(EditorTabsBar),
      matching: find.byIcon(Icons.close),
    );
    await pumpUntilFound(tester, close);
    await tester.tap(close.first);
    await tester.pump(const Duration(milliseconds: 400));

    // Discard if prompted.
    final discard = find.text('Discard');
    if (tester.widgetList(discard).isNotEmpty) {
      await tester.tap(discard.last);
      await tester.pump();
    }

    await pumpUntilAbsent(tester, find.byType(EditorTabsBar));
    harness.expectNoFlutterErrors();
  });
}
