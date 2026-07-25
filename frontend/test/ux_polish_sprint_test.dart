import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';
import 'package:robot_studio/presentation/panels/side_panel.dart';
import 'package:robot_studio/presentation/sidebar/app_sidebar.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/widgets/environment_prompt_toast.dart';
import 'package:robot_studio/presentation/widgets/error_dialog.dart';

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
      friendlyErrorRecovery('FileNotFoundError: No such file or directory'),
      'It may have been moved or deleted. Refresh and try again.',
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
              message: 'Select an existing environment or create one to enable '
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
    expect(find.textContaining('Select an existing environment'), findsOneWidget);
    expect(find.text('Create Environment'), findsOneWidget);
    // The ✕ is the only dismiss affordance; "Skip" was redundant.
    expect(find.text('Skip'), findsNothing);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });

  testWidgets('side rail collapses for panels that own the main view', (
    tester,
  ) async {
    for (final panel in [
      SidebarPanel.search,
      SidebarPanel.keywords,
      SidebarPanel.packages,
      SidebarPanel.plugins,
      SidebarPanel.sourceControl,
    ]) {
      expect(SidePanel.hasSideContent(panel), isFalse, reason: panel.label);
    }
    for (final panel in [
      SidebarPanel.explorer,
      SidebarPanel.tests,
      SidebarPanel.reports,
    ]) {
      expect(SidePanel.hasSideContent(panel), isTrue, reason: panel.label);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(
            panel: SidebarPanel.packages,
            workspace: workspace,
          ),
        ),
      ),
    );
    expect(find.textContaining('main view'), findsNothing);
  });

  testWidgets('bottom panel exposes only implemented tabs', (tester) async {
    expect(
      BottomPanelTab.values.map((tab) => tab.label),
      ['Console', 'Execution Logs', 'Problems'],
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BottomPanel())),
    );
    expect(find.text('OUTPUT'), findsNothing);
    expect(find.text('TERMINAL'), findsNothing);
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
