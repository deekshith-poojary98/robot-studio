import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/plugins/plugin_manager_page.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: PL-01 … PL-07 (Plugins).
///
/// Source: docs/internal/functional-test-cases.md §14
///
/// Beta: Plugin Manager is hidden from the activity bar and command palette.
/// UI cases are skipped until that surface is restored; keep the bodies intact.
const _pluginsUiHiddenForBeta =
    'Plugin Manager UI hidden for beta (sidebar + command palette)';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Finder pluginListScrollable() => find.descendant(
    of: find.byType(PluginManagerPage),
    matching: find.byType(Scrollable),
  );

  testWidgets('PL-01 plugin manager lists builtins', (tester) async {
    await harness.seedWorkspace(name: 'PL List', suffix: 'pl-01');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL List');
    await openPluginManager(tester);
    await pumpUntilFound(tester, find.text('Plugin Manager'));

    final plugins = await harness.api.listPlugins();
    expect(plugins, isNotEmpty);
    expect(
      plugins.any(
        (item) => item['is_builtin'] == true || item['builtin'] == true,
      ),
      isTrue,
    );

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-02 no layout overflow on rows', (tester) async {
    await harness.seedWorkspace(name: 'PL Overflow', suffix: 'pl-02');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL Overflow');
    await openPluginManager(tester);
    await pumpUntilFound(tester, find.byType(PluginManagerPage));
    expect(tester.takeException(), isNull);

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-03 enable disable exclusivity', (tester) async {
    final workspace = await harness.seedWorkspace(
      name: 'PL Toggle',
      suffix: 'pl-03',
    );
    harness.installTestPlugin(workspace['path'] as String);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL Toggle');
    await openPluginManager(tester);

    final pluginName = find.text('Integration Test Plugin');
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, pluginListScrollable());
    await tester.dragUntilVisible(
      pluginName,
      pluginListScrollable(),
      const Offset(0, -120),
    );
    await pumpUntilFound(tester, pluginName);
    await tester.tap(pluginName.first);
    await tester.pump(const Duration(milliseconds: 400));

    final plugins = await harness.api.listPlugins();
    final integration = plugins.firstWhere(
      (item) => item['id'] == 'integration-test-plugin',
    );
    final id = integration['id'] as String;
    if (integration['enabled'] == true) {
      await harness.api.disablePlugin(id);
    } else {
      await harness.api.enablePlugin(id);
    }
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, pluginName);

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-04 builtin enable not dead control', (tester) async {
    await harness.seedWorkspace(name: 'PL Builtin', suffix: 'pl-04');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL Builtin');
    await openPluginManager(tester);
    await pumpUntilFound(tester, find.text('Built-in'));
    // Builtin rows show Built-in instead of a dead Enable control.
    expect(find.text('Built-in'), findsWidgets);

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-05 plugin details panel', (tester) async {
    final workspace = await harness.seedWorkspace(
      name: 'PL Details',
      suffix: 'pl-05',
    );
    harness.installTestPlugin(workspace['path'] as String);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL Details');
    await openPluginManager(tester);
    final pluginName = find.text('Integration Test Plugin');
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, pluginListScrollable());
    await tester.dragUntilVisible(
      pluginName,
      pluginListScrollable(),
      const Offset(0, -120),
    );
    await tester.tap(pluginName.first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reload'), findsWidgets);

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-06 reload plugins', (tester) async {
    await harness.seedWorkspace(name: 'PL Reload', suffix: 'pl-06');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'PL Reload');
    await openPluginManager(tester);
    await tapText(tester, 'Refresh');
    await pumpUntilFound(tester, find.byType(PluginManagerPage));
    await harness.api.refreshPlugins();

    harness.expectNoFlutterErrors();
  }, skip: _pluginsUiHiddenForBeta);

  testWidgets('PL-07 plugins offline', (tester) async {}, skip: true);
}
