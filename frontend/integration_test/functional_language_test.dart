import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: LG-01 … LG-10 (Language intelligence / Problems).
///
/// Source: Robot Studio — Functional Test Cases.md §8
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  const broken = '*** Test Cases ***\nBroken\n    UnknownKeyword    x\n';
  const clean = '*** Test Cases ***\nSample\n    Log    ok\n';
  const withKeyword = '''*** Keywords ***
Hello World
    [Documentation]    Hi from LG
    Log    hi

*** Test Cases ***
Run Hello
    Hello World
''';

  Future<String> seedBrokenSuite({
    required String workspace,
    required String suffix,
    required String project,
    bool installRobot = true,
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(
      name: '$suffix-env',
      installRobot: installRobot,
    );
    final created = await harness.seedProject(name: project);
    final path = '${created['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: broken);
    return path;
  }

  testWidgets('LG-01 live diagnostics show unknown keyword', (tester) async {
    await seedBrokenSuite(
      workspace: 'LG Live',
      suffix: 'lg-01',
      project: 'LgLive',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Live');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgLive',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
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

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-02 fix clears diagnostic', (tester) async {
    final path = await seedBrokenSuite(
      workspace: 'LG Fix',
      suffix: 'lg-02',
      project: 'LgFix',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Fix');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgFix',
    );
    await pumpUntilFound(
      tester,
      find.textContaining('PROBLEMS '),
      timeout: const Duration(seconds: 90),
    );

    // Persist a clean suite, close tab, reopen — editor reloads fixed content.
    await harness.api.writeFile(path: path, content: clean);
    final close = find.byIcon(Icons.close);
    await pumpUntilFound(tester, close);
    await tester.tap(close.first);
    await tester.pump(const Duration(milliseconds: 400));
    final discard = find.text('Discard');
    if (tester.widgetList(discard).isNotEmpty) {
      await tester.tap(discard.last);
      await tester.pump();
    }
    final reload = find.textContaining('Reload');
    if (tester.widgetList(reload).isNotEmpty) {
      await tester.tap(reload.first);
      await tester.pump();
    }

    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgFix',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await tester.pump(const Duration(seconds: 2));

    await openBottomTab(tester, 'Problems');
    await pumpUntilFound(
      tester,
      find.textContaining('No problems found'),
      timeout: const Duration(seconds: 60),
    );
    expect(find.textContaining('UnknownKeyword'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-03 completions include relevant keywords', (tester) async {
    await harness.seedWorkspace(name: 'LG Complete', suffix: 'lg-03');
    await harness.seedEnvironment(name: 'lg-03-env', installRobot: true);
    final project = await harness.seedProject(name: 'LgComplete');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: withKeyword);
    await harness.api.rebuildIndex();

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Complete');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgComplete',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));

    final completion = await harness.api.languageCompletion(
      filePath: path,
      content: withKeyword,
      line: 8,
      column: 5,
      query: 'Hel',
    );
    final items = completion['items'] as List<dynamic>? ?? const [];
    final labels = items
        .map((item) => (item as Map<String, dynamic>)['label']?.toString() ?? '')
        .toList();
    expect(labels.any((label) => label.contains('Hello')), isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-04 hover lookup does not crash', (tester) async {
    await harness.seedWorkspace(name: 'LG Hover', suffix: 'lg-04');
    await harness.seedEnvironment(name: 'lg-04-env', installRobot: true);
    final project = await harness.seedProject(name: 'LgHover');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: withKeyword);
    await harness.api.rebuildIndex();

    final hover = await harness.api.languageHover(name: 'Hello World');
    // Hover may be null if index still settling; must not throw.
    expect(hover == null || hover['name'] != null, isTrue);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Hover');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgHover',
    );
    await tapEditorMenuAction(tester, 'hover');
    await tester.pump(const Duration(milliseconds: 500));

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-05 go to definition resolves user keyword', (tester) async {
    await harness.seedWorkspace(name: 'LG Def', suffix: 'lg-05');
    await harness.seedEnvironment(name: 'lg-05-env', installRobot: true);
    final project = await harness.seedProject(name: 'LgDef');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: withKeyword);
    await harness.api.rebuildIndex();

    final definition = await harness.api.languageDefinition(name: 'Hello World');
    expect(definition, isNotNull);
    expect(definition!['name'], 'Hello World');
    expect(definition['file_path'], contains('sample.robot'));

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Def');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgDef',
    );
    await tapEditorMenuAction(tester, 'definition');
    await tester.pump(const Duration(milliseconds: 500));

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-06 find references returns usages', (tester) async {
    await harness.seedWorkspace(name: 'LG Refs', suffix: 'lg-06');
    await harness.seedEnvironment(name: 'lg-06-env', installRobot: true);
    final project = await harness.seedProject(name: 'LgRefs');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: withKeyword);
    await harness.api.rebuildIndex();

    final refs = await harness.api.languageReferences(name: 'Hello World');
    expect(refs, isNotEmpty);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Refs');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgRefs',
    );
    await tapEditorMenuAction(tester, 'references');
    await tester.pump(const Duration(milliseconds: 500));

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-07 problems empty state for clean file', (tester) async {
    await harness.seedWorkspace(name: 'LG Empty', suffix: 'lg-07');
    await harness.seedEnvironment(name: 'lg-07-env', installRobot: true);
    final project = await harness.seedProject(name: 'LgEmpty');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: clean);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Empty');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgEmpty',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));
    await tester.pump(const Duration(seconds: 2));

    await openBottomTab(tester, 'Problems');
    await pumpUntilFound(
      tester,
      find.textContaining('No problems found'),
      timeout: const Duration(seconds: 60),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-08 problems location label format', (tester) async {
    await seedBrokenSuite(
      workspace: 'LG Loc',
      suffix: 'lg-08',
      project: 'LgLoc',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Loc');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgLoc',
    );
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

    // Basename + line + column, e.g. sample.robot:3:5
    final location = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'sample\.robot:\d+:\d+').hasMatch(widget.data!),
    );
    await pumpUntilFound(tester, location);

    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-09 collapsed problems count', (tester) async {
    await seedBrokenSuite(
      workspace: 'LG Count',
      suffix: 'lg-09',
      project: 'LgCount',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG Count');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgCount',
    );
    await pumpUntilFound(
      tester,
      find.textContaining('PROBLEMS '),
      timeout: const Duration(seconds: 90),
    );

    final collapse = find.byTooltip('Collapse panel');
    if (tester.widgetList(collapse).isNotEmpty) {
      await tester.tap(collapse.first);
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      final down = find.byIcon(Icons.keyboard_arrow_down);
      if (tester.widgetList(down).isNotEmpty) {
        await tester.tap(down.first);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await pumpUntilFound(tester, find.textContaining('PROBLEMS '));
    harness.expectNoFlutterErrors();
  });

  testWidgets('LG-10 language without env does not crash', (tester) async {
    await harness.seedWorkspace(name: 'LG NoEnv', suffix: 'lg-10');
    // Create env but leave inactive so status can show no active environment.
    await harness.seedEnvironment(
      name: 'lg-10-env',
      installRobot: false,
      activate: false,
    );
    final project = await harness.seedProject(name: 'LgNoEnv');
    final path = '${project['path']}/tests/sample.robot';
    await harness.api.writeFile(path: path, content: clean);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'LG NoEnv');
    await openRobotFileInExplorer(
      tester,
      'sample.robot',
      projectName: 'LgNoEnv',
    );
    await pumpUntilFound(tester, find.byKey(const Key('editor.page')));

    await tapEditorFormat(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tapEditorMenuAction(tester, 'hover');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    harness.expectNoFlutterErrors();
  });
}
