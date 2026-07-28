import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/file_info.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';
import 'package:robot_studio/presentation/widgets/empty_state.dart';
import 'package:robot_studio/presentation/widgets/error_dialog.dart';
import 'package:robot_studio/presentation/widgets/skeleton_list.dart';
import 'package:robot_studio/presentation/widgets/virtual_file_tree.dart';

void main() {
  testWidgets('EmptyState exposes semantics and actions', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.folder_open,
            title: 'No project',
            message: 'Open a folder to begin.',
            actionLabel: 'Open Project',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('No project'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('No project')), findsWidgets);
    await tester.tap(find.text('Open Project'));
    expect(tapped, isTrue);
  });

  testWidgets('SkeletonList renders placeholder rows', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkeletonList(rows: 4)),
      ),
    );
    expect(find.byType(SkeletonList), findsOneWidget);
  });

  testWidgets('VirtualFileTree highlights selected path', (tester) async {
    final rows = [
      FlatFileTreeRow(
        node: const FileTreeNode(
          name: 'sample.robot',
          path: '/ws/sample.robot',
          relativePath: 'sample.robot',
          isDir: false,
          suffix: '.robot',
        ),
        depth: 0,
        expanded: false,
        loading: false,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            rows: rows,
            selectedPath: '/ws/sample.robot',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('sample.robot'), findsOneWidget);
  });

  testWidgets('StatusBar omits decorative encoding chips', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(
            projectName: 'Demo',
            notification: 'Workspace synchronized',
          ),
        ),
      ),
    );
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.text('Workspace synchronized'), findsOneWidget);
    expect(find.text('UTF-8'), findsNothing);
    expect(find.text('LF'), findsNothing);
  });

  test('friendly timeout copy is actionable', () {
    expect(
      friendlyErrorSummary('TimeoutException after 0:00:30'),
      contains('longer than expected'),
    );
    expect(
      friendlyErrorRecovery('TimeoutException after 0:00:30'),
      contains('Still working'),
    );
  });
}
