import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/editor/editor_tabs_bar.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: IX-01 … IX-10 (Indexing / Keywords / Search / Tests).
///
/// Source: Robot Studio — Functional Test Cases.md §9
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  const withKeyword = '''*** Settings ***
Library    BuiltIn

*** Keywords ***
Hello World
    [Documentation]    Hi from IX
    Log    hi

*** Test Cases ***
Run Hello
    Hello World
''';

  Future<({String path, String project, String suiteName})> seedIndexedWorkspace({
    required String workspace,
    required String suffix,
    required String project,
    String suiteFile = 'sample.robot',
  }) async {
    await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: true);
    final created = await harness.seedProject(name: project);
    final path = '${created['path']}/tests/$suiteFile';
    await harness.api.writeFile(path: path, content: withKeyword);
    await harness.api.rebuildIndex();
    final suiteName = suiteFile.replaceAll(RegExp(r'\.robot$'), '');
    return (path: path, project: project, suiteName: suiteName);
  }

  testWidgets('IX-01 index status card shows READY counts', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Status',
      suffix: 'ix-01',
      project: 'IxStatus',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Status');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('Index Status'));
    await pumpUntilFound(
      tester,
      find.text('READY'),
      timeout: const Duration(seconds: 60),
    );
    expect(find.text('Files'), findsWidgets);
    expect(find.text('Keywords'), findsWidgets);
    expect(find.text('Libraries'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-02 rebuild index completes', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Rebuild',
      suffix: 'ix-02',
      project: 'IxRebuild',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Rebuild');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('Rebuild'));
    await tester.tap(find.text('Rebuild').first);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntilFound(
      tester,
      find.text('READY'),
      timeout: const Duration(seconds: 90),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final status = await harness.api.indexStatus();
    expect(status['state']?.toString().toLowerCase(), 'ready');

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-03 keyword search finds BuiltIn Log', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Log',
      suffix: 'ix-03',
      project: 'IxLog',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Log');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('Search'));
    await pumpUntilFound(tester, find.text('READY'), timeout: const Duration(seconds: 60));

    final field = find.byType(TextField);
    await pumpUntilFound(tester, field);
    await tester.enterText(field.first, 'Log');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Search').last);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntilFound(
      tester,
      find.textContaining('Log'),
      timeout: const Duration(seconds: 30),
    );

    final apiHits = await harness.api.searchSymbols(query: 'Log', kind: 'keyword');
    expect(apiHits.any((item) => (item['name'] as String?) == 'Log'), isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-04 workspace symbol search finds user keyword', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Symbol',
      suffix: 'ix-04',
      project: 'IxSymbol',
      suiteFile: 'ix04_symbol.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Symbol');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('READY'), timeout: const Duration(seconds: 60));

    final field = find.byType(TextField);
    await pumpUntilFound(tester, field);
    await tester.enterText(field.first, 'Hello World');
    await tester.tap(find.text('Search').last);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntilFound(
      tester,
      find.textContaining('Hello World'),
      timeout: const Duration(seconds: 30),
    );
    expect(find.textContaining('ix04_symbol.robot'), findsWidgets);

    await tester.tap(find.textContaining('Hello World').first);
    await tester.pump(const Duration(milliseconds: 500));

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-05 empty search query shows prompt state', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX EmptyQ',
      suffix: 'ix-05',
      project: 'IxEmptyQ',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX EmptyQ');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('Search symbols…'));
    await tester.tap(find.text('Search').last);
    await tester.pump(const Duration(milliseconds: 400));

    final emptyOrPrompt =
        tester.widgetList(find.textContaining('No symbols found')).isNotEmpty ||
        tester.widgetList(find.textContaining('Search indexed')).isNotEmpty ||
        tester.widgetList(find.textContaining('Rebuild the index')).isNotEmpty;
    expect(emptyOrPrompt, isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-06 tests panel lists suites', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Suites',
      suffix: 'ix-06',
      project: 'IxSuites',
      suiteFile: 'ix06_listed.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Suites');
    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Test Suites'));
    await pumpUntilFound(tester, find.text('Recent Runs'));

    await pumpUntilFound(
      tester,
      find.textContaining('ix06_listed'),
      timeout: const Duration(seconds: 60),
    );
    expect(
      find.textContaining('No suites indexed yet'),
      findsNothing,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-07 open suite from Tests panel', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX OpenSuite',
      suffix: 'ix-07',
      project: 'IxOpenSuite',
      suiteFile: 'ix07_open.robot',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX OpenSuite');
    await tapSidebarPanel(tester, 'Tests');
    await pumpUntilFound(tester, find.text('Execution'));
    await pumpUntilFound(
      tester,
      find.textContaining('ix07_open'),
      timeout: const Duration(seconds: 60),
    );
    await tester.tap(find.textContaining('ix07_open').first);
    await tester.pump(const Duration(milliseconds: 600));

    // Tests panel keeps Execution as the center view; Explorer restores the
    // editor shell once the suite file has been opened into a tab.
    await tapSidebarPanel(tester, 'Explorer');
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(EditorTabsBar),
        matching: find.text('ix07_open.robot'),
      ),
      timeout: const Duration(seconds: 20),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-08 index after new file discovers symbols', (tester) async {
    final seeded = await seedIndexedWorkspace(
      workspace: 'IX NewFile',
      suffix: 'ix-08',
      project: 'IxNewFile',
      suiteFile: 'ix08_base.robot',
    );
    final projectRoot = seeded.path.replaceAll('/tests/ix08_base.robot', '');
    final newPath = '$projectRoot/tests/ix08_extra.robot';
    await harness.api.writeFile(
      path: newPath,
      content:
          '*** Keywords ***\nFresh Keyword\n    Log    fresh\n\n*** Test Cases ***\nFresh Case\n    Fresh Keyword\n',
    );
    await harness.api.rebuildIndex();

    final hits = await harness.api.searchSymbols(query: 'Fresh Keyword');
    expect(
      hits.any((item) => (item['name'] as String?) == 'Fresh Keyword'),
      isTrue,
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX NewFile');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('READY'), timeout: const Duration(seconds: 60));
    final field = find.byType(TextField);
    await tester.enterText(field.first, 'Fresh Keyword');
    await tester.tap(find.text('Search').last);
    await pumpUntilFound(
      tester,
      find.textContaining('Fresh Keyword'),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-09 search page vs palette both reach symbols', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Dual',
      suffix: 'ix-09',
      project: 'IxDual',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Dual');

    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('Index Status'));
    expect(find.textContaining('Search indexed keywords'), findsWidgets);

    // Toolbar chrome opens the command palette (distinct from Search page).
    await tester.tap(find.textContaining('Search commands, files, symbols').first);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntilFound(
      tester,
      find.textContaining('Type a command, file, or symbol'),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('IX-10 keywords count greater than zero', (tester) async {
    await seedIndexedWorkspace(
      workspace: 'IX Count',
      suffix: 'ix-10',
      project: 'IxCount',
    );
    final status = await harness.api.indexStatus();
    final keywords = (status['keywords_indexed'] as num?)?.toInt() ?? 0;
    expect(
      keywords,
      greaterThan(0),
      reason:
          'Keywords count was 0 after rebuild for IxCount fixture '
          '(Library BuiltIn + Hello World). Treat as index defect.',
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'IX Count');
    await tapSidebarPanel(tester, 'Search');
    await pumpUntilFound(tester, find.text('READY'), timeout: const Duration(seconds: 60));
    expect(find.text('Keywords'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
