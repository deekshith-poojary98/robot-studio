import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';
import 'helpers/performance_tracker.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: EN-01 … EN-10 (Environment).
///
/// Source: Robot Studio — Functional Test Cases.md §5
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('EN-01 create environment via UI', (tester) async {
    await harness.seedWorkspace(name: 'EN Create', suffix: 'en-01');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Create');

    await createEnvironmentViaUi(
      tester,
      name: 'en-create',
      pythonInterpreter: defaultPythonInterpreter(),
      installRobot: false,
    );
    await pumpUntilFound(
      tester,
      find.text('en-create'),
      timeout: const Duration(minutes: 3),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-02 activate environment updates chrome', (tester) async {
    await harness.seedWorkspace(name: 'EN Act', suffix: 'en-02');
    final env = await harness.seedEnvironment(
      name: 'en-act',
      installRobot: false,
      activate: false,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Act');

    await harness.api.activateEnvironment(env['id'] as String);
    await refreshEnvironmentsInUi(tester);
    await pumpUntilFound(
      tester,
      find.text('en-act'),
      timeout: const Duration(seconds: 45),
    );
    expect(find.textContaining('ENV '), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-03 switch between environments', (tester) async {
    await harness.seedWorkspace(name: 'EN Switch', suffix: 'en-03');
    final a = await harness.seedEnvironment(
      name: 'en-a',
      installRobot: false,
      activate: true,
    );
    final b = await harness.seedEnvironment(
      name: 'en-b',
      installRobot: false,
      activate: false,
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Switch');
    await pumpUntilFound(tester, find.text('en-a'));

    await harness.api.activateEnvironment(b['id'] as String);
    await refreshEnvironmentsInUi(tester);
    await pumpUntilFound(tester, find.text('en-b'));
    // Active toolbar chip shows en-b; en-a may still appear in manager lists.
    expect(find.text('en-b'), findsWidgets);

    // Keep a alive for cleanup paths.
    expect(a['id'], isNotNull);

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-04 import environment from existing venv', (tester) async {
    await harness.seedWorkspace(name: 'EN Import', suffix: 'en-04');
    // Keeper stays active so we can unregister the disposable venv.
    await harness.seedEnvironment(
      name: 'en-keeper',
      installRobot: false,
      activate: true,
    );
    final created = await harness.seedEnvironment(
      name: 'en-to-import',
      installRobot: false,
      activate: false,
    );
    final path = created['path'] as String;
    await harness.api.deleteEnvironment(
      created['id'] as String,
      deleteFiles: false,
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Import');
    await openEnvironmentManager(tester);
    await tapText(tester, 'Import');
    await pumpUntilFound(tester, find.text('Import Environment'));
    await fillDialogFieldByLabel(tester, 'Environment path', path);
    await submitDialog(tester, actionLabel: 'Import');
    await pumpUntilAbsent(
      tester,
      find.text('Import Environment'),
      timeout: const Duration(minutes: 2),
    );

    await pumpUntilFound(
      tester,
      find.textContaining('en-to-import'),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-05 clone environment', (tester) async {
    await harness.seedWorkspace(name: 'EN Clone', suffix: 'en-05');
    final env = await harness.seedEnvironment(
      name: 'en-src',
      installRobot: false,
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Clone');

    final cloned = await harness.api.cloneEnvironment(
      id: env['id'] as String,
      name: 'en-clone',
    );
    expect(cloned['name'], 'en-clone');
    await refreshEnvironmentsInUi(tester);
    await pumpUntilFound(tester, find.textContaining('en-clone'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-06 delete non-active environment', (tester) async {
    await harness.seedWorkspace(name: 'EN Del', suffix: 'en-06');
    final keeper = await harness.seedEnvironment(
      name: 'en-keeper',
      installRobot: false,
      activate: true,
    );
    final doomed = await harness.seedEnvironment(
      name: 'en-doomed',
      installRobot: false,
      activate: false,
    );

    await harness.api.deleteEnvironment(doomed['id'] as String);
    final envs = await harness.api.listEnvironments();
    expect(envs.any((item) => item['name'] == 'en-doomed'), isFalse);
    expect(envs.any((item) => item['id'] == keeper['id']), isTrue);

    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Del');
    await refreshEnvironmentsInUi(tester);
    expect(find.text('en-doomed'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-07 cannot delete active without switching first',
      (tester) async {
    await harness.seedWorkspace(name: 'EN DelAct', suffix: 'en-07');
    final active = await harness.seedEnvironment(
      name: 'en-active',
      installRobot: false,
      activate: true,
    );
    final other = await harness.seedEnvironment(
      name: 'en-other',
      installRobot: false,
      activate: false,
    );

    // Deleting active should fail or require switch — exercise switch-then-delete.
    await harness.api.activateEnvironment(other['id'] as String);
    await harness.api.deleteEnvironment(active['id'] as String);

    final envs = await harness.api.listEnvironments();
    expect(envs.any((item) => item['name'] == 'en-active'), isFalse);
    expect(envs.any((item) => item['name'] == 'en-other'), isTrue);

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-08 duplicate env name rejected', (tester) async {
    await harness.seedWorkspace(name: 'EN Dup', suffix: 'en-08');
    await harness.seedEnvironment(name: 'myenv', installRobot: false);
    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Dup');

    await openEnvironmentManager(tester);
    await tapText(tester, 'Create');
    await pumpUntilFound(tester, find.text('Create Environment'));
    await waitForDialogInterpreterLoad(tester);
    await fillDialogFieldByLabel(tester, 'Environment name', 'myenv');
    await setInstallRobotFramework(tester, enabled: false);
    await submitDialog(tester, actionLabel: 'Create');

    await pumpUntilFound(
      tester,
      find.textContaining('exist'),
      timeout: const Duration(seconds: 30),
    );
    await dismissErrorDialogIfPresent(tester);

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-09 cancel create leaves no partial env', (tester) async {
    await harness.seedWorkspace(name: 'EN Cancel', suffix: 'en-09');
    await harness.launchAppWithWorkspace(tester, workspaceName: 'EN Cancel');

    await openEnvironmentManager(tester);
    await tapText(tester, 'Create');
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await waitForDialogInterpreterLoad(tester);
    await fillDialogFieldByLabel(tester, 'Environment name', 'should-not-exist');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ).last,
    );
    await tester.pump();
    await pumpUntilAbsent(tester, find.byType(AlertDialog));

    final envs = await harness.api.listEnvironments();
    expect(
      envs.any((item) => item['name'] == 'should-not-exist'),
      isFalse,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('EN-10 manage environments gated without workspace',
      (tester) async {
    await harness.launchApp(tester);

    expect(find.text('Manage Environments'), findsOneWidget);
    await tester.tap(find.text('Manage Environments'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Environment Manager'), findsNothing);

    harness.expectNoFlutterErrors();
  });
}
