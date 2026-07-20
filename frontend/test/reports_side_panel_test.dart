import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/presentation/panels/side_panel.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';

void main() {
  final workspace = WorkspaceInfo(
    id: 'ws-1',
    name: 'robot-files',
    path: '/tmp/robot-files',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  final run = ExecutionInfo(
    id: 'run-1',
    workspaceId: 'ws-1',
    projectId: 'p1',
    environmentId: 'e1',
    projectName: 'Amazon',
    suite: 'tests/sample.robot',
    status: ExecutionStatus.failed,
    startedAt: DateTime.utc(2026, 1, 1),
  );

  testWidgets('reports side panel lists recent runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(
            panel: SidebarPanel.reports,
            workspace: workspace,
            recentRuns: [run],
          ),
        ),
      ),
    );

    expect(find.textContaining('Amazon'), findsOneWidget);
    expect(find.text('No reports yet. Run a suite to generate artifacts.'),
        findsNothing);
  });

  testWidgets('reports side panel empty state when no runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(
            panel: SidebarPanel.reports,
            workspace: workspace,
            recentRuns: const [],
          ),
        ),
      ),
    );

    expect(find.text('No reports yet. Run a suite to generate artifacts.'),
        findsOneWidget);
  });
}
