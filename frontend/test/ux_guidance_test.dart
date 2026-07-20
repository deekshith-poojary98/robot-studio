import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/project_info.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/presentation/widgets/guidance_dialog.dart';
import 'package:robot_studio/presentation/workspace/welcome_screen.dart';

void main() {
  testWidgets('guidance dialog offers primary next step', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showGuidanceDialog(
                  context: context,
                  title: 'Workspace needed',
                  message: 'Open a workspace to continue.',
                  primaryLabel: 'Open Workspace…',
                  onPrimary: () => opened = true,
                );
              },
              child: const Text('Trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Workspace needed'), findsOneWidget);
    await tester.tap(find.text('Open Workspace…'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('recent items expose full path tooltips', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeScreen(
            recentWorkspaces: [
              WorkspaceInfo(
                id: '1',
                name: 'robot-files-very-long-name',
                path: '/Users/demo/robot-files-very-long-name',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ],
            recentProjects: [
              ProjectInfo(
                id: 'p1',
                workspaceId: '1',
                name: 'Amazon',
                path: '/Users/demo/robot-files/Amazon',
                type: ProjectType.browser,
                createdAt: DateTime.utc(2026, 1, 2),
              ),
            ],
            isLoadingRecent: false,
            onNewWorkspace: () {},
            onOpenWorkspace: () {},
            onOpenRecentWorkspace: (_) {},
            onOpenRecentProject: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byTooltip('robot-files-very-long-name\n/Users/demo/robot-files-very-long-name'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Amazon\n/Users/demo/robot-files/Amazon'),
      findsOneWidget,
    );
  });
}
