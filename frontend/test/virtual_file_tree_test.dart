import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/file_info.dart';
import 'package:robot_studio/presentation/widgets/virtual_file_tree.dart';

void main() {
  testWidgets('VirtualFileTree builds only visible rows', (tester) async {
    final rows = List.generate(
      200,
      (i) => FlatFileTreeRow(
        node: FileTreeNode(
          name: 'suite_$i.robot',
          path: '/tmp/suite_$i.robot',
          relativePath: 'suite_$i.robot',
          isDir: false,
          children: const [],
        ),
        depth: 0,
        expanded: false,
        loading: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: VirtualFileTree(
              rows: rows,
              onOpenFile: (_) {},
              onToggleDirectory: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('virtual-file-tree')), findsOneWidget);
    // Virtualized: far rows are not in the tree yet.
    expect(find.text('suite_0.robot'), findsOneWidget);
    expect(find.text('suite_199.robot'), findsNothing);
  });

  testWidgets('VirtualFileTree toggles directories', (tester) async {
    var toggled = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            rows: [
              FlatFileTreeRow(
                node: FileTreeNode(
                  name: 'tests',
                  path: '/tmp/tests',
                  relativePath: 'tests',
                  isDir: true,
                  hasChildren: true,
                  children: const [],
                ),
                depth: 0,
                expanded: false,
                loading: false,
              ),
            ],
            onOpenFile: (_) {},
            onToggleDirectory: (path) => toggled = path,
          ),
        ),
      ),
    );

    await tester.tap(find.text('tests'));
    expect(toggled, '/tmp/tests');
  });
}
