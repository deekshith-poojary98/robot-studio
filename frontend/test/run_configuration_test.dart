import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/reports/run_details_panel.dart';
import 'package:robot_studio/presentation/run_configuration/manage_run_configurations_dialog.dart';
import 'package:robot_studio/presentation/run_configuration/run_configuration_edit_dialog.dart';
import 'package:robot_studio/presentation/toolbar/app_toolbar.dart';

void main() {
  final sample = RunConfigurationInfo(
    id: 'cfg-1',
    name: 'Smoke - Staging',
    includeTags: const ['smoke'],
    excludeTags: const ['wip'],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  testWidgets('toolbar shows Default then named configuration', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'Demo',
            environmentLabel: 'robot-main',
            backendConnected: true,
            runConfigurationsEnabled: true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('Default'), findsOneWidget);
    expect(find.byKey(const Key('toolbar.run-configuration')), findsOneWidget);
    expect(find.byKey(const Key('toolbar.run')), findsOneWidget);
    expect(find.byKey(const Key('toolbar.run-project')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'Demo',
            environmentLabel: 'robot-main',
            backendConnected: true,
            runConfigurationsEnabled: true,
            runConfigurations: [sample],
            activeRunConfigurationId: sample.id,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Smoke - Staging'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
  });

  testWidgets('selector menu offers Default, New, and Manage', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var managed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AppToolbar(
            projectLabel: 'Demo',
            environmentLabel: 'robot-main',
            backendConnected: true,
            runConfigurationsEnabled: true,
            runConfigurations: [sample],
            activeRunConfigurationId: sample.id,
            onManageRunConfigurations: () => managed = true,
            onRun: () {},
            onRunProject: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('toolbar.run-configuration')));
    await tester.pumpAndSettle();

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('New Configuration…'), findsOneWidget);
    expect(find.text('Manage Configurations…'), findsOneWidget);

    await tester.tap(find.text('Manage Configurations…'));
    await tester.pumpAndSettle();
    expect(managed, isTrue);
  });

  testWidgets('new configuration dialog collects structured fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final future = showRunConfigurationEditDialog(
      tester.element(find.byType(SizedBox)),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Run Configuration'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Smoke - Dev');
    await tester.enterText(find.byType(TextField).at(1), 'smoke, critical');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final draft = await future;
    expect(draft, isNotNull);
    expect(draft!.name, 'Smoke - Dev');
    expect(draft.includeTags, ['smoke', 'critical']);
    expect(draft.environmentId, isNull);
  });

  testWidgets('manage dialog duplicates as a first-class action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = _ConfigGateway(sample);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final future = showManageRunConfigurationsDialog(
      tester.element(find.byType(SizedBox)),
      gateway: gateway,
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Run Configurations'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(gateway.duplicatedId, sample.id);
    expect(find.text('Smoke - Staging copy'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await future;
  });

  testWidgets('run details records the configuration used', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: RunDetailsPanel(
            run: ExecutionInfo(
              id: 'run-1',
              workspaceId: 'ws',
              projectId: 'p1',
              environmentId: 'e1',
              projectName: 'Checkout',
              suite: 'tests/checkout.robot',
              status: ExecutionStatus.finished,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              environmentName: 'robot-main',
              configurationId: 'cfg-1',
              configurationName: 'Smoke - Staging',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('Smoke - Staging'), findsOneWidget);
    expect(find.text('robot-main'), findsOneWidget);
  });
}

class _ConfigGateway implements TransportGateway {
  _ConfigGateway(RunConfigurationInfo initial) : items = [initial];

  final List<RunConfigurationInfo> items;
  String? duplicatedId;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<RunConfigurationListInfo> listRunConfigurations() async {
    return RunConfigurationListInfo(
      activeId: items.isEmpty ? null : items.first.id,
      configurations: List.unmodifiable(items),
    );
  }

  @override
  Future<RunConfigurationInfo> duplicateRunConfiguration(
    String configurationId,
  ) async {
    duplicatedId = configurationId;
    final source = items.firstWhere((item) => item.id == configurationId);
    final copy = RunConfigurationInfo(
      id: 'cfg-copy',
      name: '${source.name} copy',
      includeTags: source.includeTags,
      excludeTags: source.excludeTags,
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    items.add(copy);
    return copy;
  }
}
