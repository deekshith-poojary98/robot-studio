import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/presentation/panels/side_panel.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/widgets/explorer_tree.dart';

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
    outputDir: '/tmp/robot-files/Reports/Run-20260101-120000-123456',
  );

  testWidgets('reports side panel lists runs with run number', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(
            panel: SidebarPanel.reports,
            workspace: workspace,
            recentRuns: [run],
            onSelectReport: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Runs'), findsOneWidget);
    expect(find.textContaining('Run 20260101-120000'), findsOneWidget);
    expect(find.text('Open Reports'), findsNothing);
    expect(find.text('No reports yet'), findsNothing);
  });

  testWidgets('selected report is highlighted in the runs list', (
    tester,
  ) async {
    final other = ExecutionInfo(
      id: 'run-2',
      workspaceId: 'ws-1',
      projectId: 'p1',
      environmentId: 'e1',
      projectName: 'Amazon',
      suite: 'tests/other.robot',
      status: ExecutionStatus.finished,
      startedAt: DateTime.utc(2026, 1, 2),
      outputDir: '/tmp/robot-files/Reports/Run-20260102-120000-123456',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidePanel(
            panel: SidebarPanel.reports,
            workspace: workspace,
            recentRuns: [run, other],
            selectedReport: run,
            onSelectReport: (_) {},
          ),
        ),
      ),
    );

    final selected = tester.widget<ExplorerTreeItem>(
      find.ancestor(
        of: find.textContaining('Run 20260101-120000'),
        matching: find.byType(ExplorerTreeItem),
      ),
    );
    final unselected = tester.widget<ExplorerTreeItem>(
      find.ancestor(
        of: find.textContaining('Run 20260102-120000'),
        matching: find.byType(ExplorerTreeItem),
      ),
    );
    expect(selected.selected, isTrue);
    expect(unselected.selected, isFalse);
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

    expect(find.text('No reports yet'), findsOneWidget);
    expect(
      find.text('Run your first Robot Framework suite to generate a report.'),
      findsOneWidget,
    );
  });
}
