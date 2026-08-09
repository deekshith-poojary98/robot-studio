import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';

/// Plugin discovery / lifecycle via API.
///
/// Beta: Plugin Manager UI is hidden from the activity bar and command palette,
/// so this suite covers backend plugin APIs only. Restore UI coverage when the
/// surface is re-enabled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('plugin discovery and lifecycle actions (API)', (tester) async {
    final workspace = await harness.seedWorkspace(
      name: 'Plugin Flow WS',
      suffix: 'plugins',
    );
    harness.installTestPlugin(workspace['path'] as String);

    await harness.launchAppWithWorkspace(
      tester,
      workspaceName: 'Plugin Flow WS',
    );

    final plugins = await harness.api.refreshPlugins();
    final integration = plugins.firstWhere(
      (item) => item['id'] == 'integration-test-plugin',
      orElse: () => <String, dynamic>{},
    );
    expect(
      integration,
      isNotEmpty,
      reason:
          'Expected workspace plugin after refresh; got '
          '${plugins.map((item) => item['id']).toList()}',
    );

    final pluginId = integration['id'] as String;
    if (integration['enabled'] == true) {
      await harness.api.disablePlugin(pluginId);
    } else {
      await harness.api.enablePlugin(pluginId);
    }
    await harness.api.reloadPlugin(pluginId);

    harness.expectNoFlutterErrors();
  });
}
