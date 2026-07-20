import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/plugins/plugin_manager_page.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

Finder _pluginListScrollable() {
  return find.descendant(
    of: find.byType(PluginManagerPage),
    matching: find.byType(Scrollable),
  );
}

Future<void> _refreshAndShowPlugin(
  WidgetTester tester, {
  required Finder pluginName,
}) async {
  await tapText(tester, 'Refresh');
  await pumpUntilAbsent(
    tester,
    find.descendant(
      of: find.byType(PluginManagerPage),
      matching: find.byType(CircularProgressIndicator),
    ),
    timeout: const Duration(seconds: 20),
  );
  await pumpUntilFound(tester, _pluginListScrollable());
  await tester.dragUntilVisible(
    pluginName,
    _pluginListScrollable(),
    const Offset(0, -120),
  );
  await pumpUntilFound(tester, pluginName);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('plugin discovery and lifecycle actions', (tester) async {
    final workspace = await harness.seedWorkspace(
      name: 'Plugin Flow WS',
      suffix: 'plugins',
    );
    harness.installTestPlugin(workspace['path'] as String);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'Plugin Flow WS');
    await openPluginManager(tester);

    final pluginName = find.text('Integration Test Plugin');
    await _refreshAndShowPlugin(tester, pluginName: pluginName);

    final plugins = await harness.api.listPlugins();
    final integration = plugins.firstWhere(
      (item) => item['id'] == 'integration-test-plugin',
      orElse: () => <String, dynamic>{},
    );
    expect(
      integration,
      isNotEmpty,
      reason: 'Expected workspace plugin after refresh; got '
          '${plugins.map((item) => item['id']).toList()}',
    );

    final pluginId = integration['id'] as String;
    if (integration['enabled'] == true) {
      await harness.api.disablePlugin(pluginId);
    } else {
      await harness.api.enablePlugin(pluginId);
    }
    await _refreshAndShowPlugin(tester, pluginName: pluginName);

    await harness.api.reloadPlugin(pluginId);
    await _refreshAndShowPlugin(tester, pluginName: pluginName);

    harness.expectNoFlutterErrors();
  });
}
