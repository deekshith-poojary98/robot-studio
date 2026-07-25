import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/plugin_info.dart';
import 'package:robot_studio/presentation/plugins/plugin_manager_page.dart';

void main() {
  testWidgets('PluginManagerPage shows plugins and actions', (
    WidgetTester tester,
  ) async {
    const plugin = PluginInfo(
      id: 'demo',
      name: 'Demo Plugin',
      version: '1.0.0',
      status: 'enabled',
      enabled: true,
      capabilities: ['toolbar-action'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginManagerPage(
            plugins: const [plugin],
            isLoading: false,
            selected: plugin,
            onRefresh: () {},
            onSelect: (_) {},
            onEnable: (_) {},
            onDisable: (_) {},
            onReload: (_) {},
            onOpenFolder: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Demo Plugin'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.text('Enable'), findsNothing);
    expect(find.text('toolbar-action'), findsOneWidget);
  });

  testWidgets('PluginManagerPage shows Enable when plugin is disabled', (
    WidgetTester tester,
  ) async {
    const plugin = PluginInfo(
      id: 'demo',
      name: 'Demo Plugin',
      version: '1.0.0',
      status: 'disabled',
      enabled: false,
      capabilities: ['toolbar-action'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginManagerPage(
            plugins: const [plugin],
            isLoading: false,
            selected: plugin,
            onRefresh: () {},
            onSelect: (_) {},
            onEnable: (_) {},
            onDisable: (_) {},
            onReload: (_) {},
            onOpenFolder: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Enable'), findsWidgets);
    expect(find.text('Disable'), findsNothing);
  });

  testWidgets('PluginManagerPage shows empty state', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginManagerPage(
            plugins: const [],
            isLoading: false,
            selected: null,
            onRefresh: () {},
            onSelect: (_) {},
            onEnable: (_) {},
            onDisable: (_) {},
            onReload: (_) {},
            onOpenFolder: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('No plugins discovered yet.'), findsOneWidget);
  });
}
