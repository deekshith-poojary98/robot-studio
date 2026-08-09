import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';
import 'package:robot_studio/presentation/panels/side_panel.dart';
import 'package:robot_studio/presentation/sidebar/app_sidebar.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/widgets/environment_prompt_toast.dart';
import 'package:robot_studio/presentation/widgets/error_dialog.dart';
import 'package:robot_studio/presentation/environment/python_install_guidance.dart';

void main() {
  final workspace = WorkspaceInfo(
    id: 'ws-1',
    name: 'demo',
    path: '/tmp/demo',
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('error dialog hides raw detail until expanded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showFriendlyErrorDialog(
                  context: context,
                  title: 'Could not save the file',
                  error: Exception('SocketException: Connection refused'),
                ),
                child: const Text('boom'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('boom'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save the file'), findsOneWidget);
    expect(
      find.text('Robot Studio could not reach its backend service.'),
      findsOneWidget,
    );
    expect(
      find.text('Make sure the backend is running, then try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('SocketException'), findsNothing);

    await tester.tap(find.byKey(const Key('error.show-details')));
    await tester.pumpAndSettle();
    expect(find.textContaining('SocketException'), findsOneWidget);
  });

  test('error copy maps common failures to plain language', () {
    expect(
      friendlyErrorSummary('OSError: [Errno 13] Permission denied'),
      'Robot Studio is not allowed to use that file or folder.',
    );
    expect(
      friendlyErrorSummary(
        "Path does not exist: '/Users/demo/Desktop/OrangeHRM/Projects/test-project'",
      ),
      'Robot Studio could not find that project or folder.',
    );
    expect(
      friendlyErrorRecovery('FileNotFoundError: No such file or directory'),
      contains('deleted, moved, or renamed'),
    );
    expect(
      friendlyErrorRecovery(
        "Path does not exist: '/Users/demo/Desktop/OrangeHRM/Projects/test-project'",
      ),
      contains('deleted, moved, or renamed'),
    );

    expect(
      friendlyErrorSummary(
        'Workspace folder is no longer on disk: /Users/demo/MyProject. '
        'Reopen or restore it before saving.',
      ),
      'The folder for this workspace was deleted outside Robot Studio.',
    );
    expect(
      friendlyErrorRecovery(
        'Project folder is no longer on disk: /Users/demo/MyProject. '
        'Reopen or restore it before saving.',
      ),
      contains('not recreated'),
    );

    expect(
      friendlyErrorSummary('Not a Git repository'),
      'This folder is not a Git repository.',
    );
    expect(
      friendlyErrorRecovery('Commit message is required'),
      contains('commit box'),
    );
    expect(
      friendlyErrorSummary('Open a project before running tests'),
      'Open a project first to continue.',
    );
    expect(
      friendlyErrorSummary(
        'Exception: No Python interpreter found on this machine.',
      ),
      PythonInstallGuidance.summary,
    );
    expect(
      friendlyErrorRecovery(
        'Exception: No Python interpreter found on this machine.',
      ),
      PythonInstallGuidance.shortRecovery,
    );
    expect(
      friendlyErrorSummary(
        'Failed to install Robot Framework: Traceback...\n'
        'File ".../pip/__main__.py"\n'
        'if sys.path[0] in ("", os.getcwd()):',
      ),
      'Could not install Robot Framework into the new environment.',
    );
    expect(
      friendlyErrorRecovery(
        'Failed to install Robot Framework: FileNotFoundError: '
        '[Errno 2] No such file or directory\ngetcwd',
      ),
      contains('working directory'),
    );
    expect(
      friendlyErrorSummary("Name cannot contain path separators"),
      "Name cannot contain path separators",
    );
    expect(
      friendlyErrorSummary('Request failed (500)'),
      'The backend rejected that request.',
    );
    // Unknown but human backend detail should surface, not the generic line.
    expect(
      friendlyErrorSummary('Suite filter matched no tests'),
      'Suite filter matched no tests',
    );
    expect(
      friendlyErrorSummary('That action did not finish.'),
      isNot(equals('')), // sanity
    );
  });

  test('raw exceptions never become the user-facing summary', () {
    expect(
      friendlyErrorSummary("KeyError: 'project_id'"),
      'Something went wrong while handling that action.',
    );
    expect(
      friendlyErrorSummary('Future not completed'),
      'Something went wrong while handling that action.',
    );
    expect(
      friendlyErrorSummary(
        'Traceback (most recent call last):\n  File "x.py", line 1\nKeyError',
      ),
      'Something went wrong while handling that action.',
    );
    expect(
      friendlyErrorSummary('TimeoutException after 0:00:30'),
      'That is taking longer than expected.',
    );
  });

  test('cleanErrorMessage strips exception wrappers', () {
    expect(
      cleanErrorMessage("GatewayException: Path does not exist: '/tmp/gone'"),
      "Path does not exist: '/tmp/gone'",
    );
    expect(
      cleanErrorMessage('Exception: Commit message is required'),
      'Commit message is required',
    );
  });

  testWidgets('environment toast leads with a title and next step', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            EnvironmentPromptToast(
              title: 'Python environment required',
              message:
                  'Select an existing environment or create one to enable '
                  'Robot Framework features.',
              actions: [
                EnvironmentPromptAction(
                  label: 'Create Environment',
                  primary: true,
                  onPressed: () {},
                ),
                EnvironmentPromptAction(
                  label: 'Select Existing',
                  onPressed: () {},
                ),
              ],
              onDismiss: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Python environment required'), findsOneWidget);
    expect(
      find.textContaining('Select an existing environment'),
      findsOneWidget,
    );
    expect(find.text('Create Environment'), findsOneWidget);
    // The ✕ is the only dismiss affordance; "Skip" was redundant.
    expect(find.text('Skip'), findsNothing);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });

  testWidgets('continue-anyway warning offers Close and Continue anyways', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showContinueAnywayDialog(
                  context: context,
                  title: 'Could not open project',
                  error: Exception(
                    "'/tmp/empty' does not look like a Robot Framework project "
                    "(expected .robot files, requirements.txt, pyproject.toml, or robot.yaml).",
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('This folder does not look like a Robot Framework project.'),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Continue anyways'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('warning.continue')));
    await tester.pumpAndSettle();
    expect(find.text('Continue anyways'), findsNothing);
  });

  testWidgets('side rail collapses for panels that own the main view', (
    tester,
  ) async {
    for (final panel in [
      SidebarPanel.packages,
      SidebarPanel.plugins,
      SidebarPanel.sourceControl,
      SidebarPanel.insights,
    ]) {
      expect(SidePanel.hasSideContent(panel), isFalse, reason: panel.label);
    }
    for (final panel in [
      SidebarPanel.explorer,
      SidebarPanel.search,
      SidebarPanel.tests,
      SidebarPanel.reports,
    ]) {
      expect(SidePanel.hasSideContent(panel), isTrue, reason: panel.label);
    }
    expect(SidePanel.hasSideContent(SidebarPanel.insights), isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(panel: SidebarPanel.packages, workspace: workspace),
        ),
      ),
    );
    expect(find.textContaining('main view'), findsNothing);
  });

  testWidgets('bottom panel exposes only implemented tabs', (tester) async {
    expect(BottomPanelTab.values.map((tab) => tab.label), [
      'Terminal',
      'Problems',
    ]);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BottomPanel())),
    );
    expect(find.text('Console'), findsNothing);
    expect(find.text('OUTPUT'), findsNothing);
    expect(find.text('EXECUTION LOGS'), findsNothing);
  });

  testWidgets('sidebar omits Settings until it is wired up', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSidebar(
            activePanel: SidebarPanel.explorer,
            onPanelSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip(SidebarPanel.explorer.tooltip), findsOneWidget);
  });
}
