import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/test_explorer_info.dart';
import 'package:robot_studio/presentation/tests/test_explorer_panel.dart';

void main() {
  TestNodeInfo sampleTree({TestNodeStatus status = TestNodeStatus.notRun}) {
    return TestNodeInfo(
      id: 'workspace:1',
      kind: 'workspace',
      name: 'Demo WS',
      children: [
        TestNodeInfo(
          id: 'project:1',
          kind: 'project',
          name: 'Shop',
          children: [
            TestNodeInfo(
              id: 'suite:1',
              kind: 'suite',
              name: 'checkout',
              path: '/tmp/checkout.robot',
              children: [
                TestNodeInfo(
                  id: 'test:1',
                  kind: 'test',
                  name: 'Pay',
                  path: '/tmp/checkout.robot',
                  line: 4,
                  status: status,
                  tags: const ['smoke'],
                ),
                const TestNodeInfo(
                  id: 'task:1',
                  kind: 'task',
                  name: 'Nightly',
                  path: '/tmp/tasks.robot',
                  line: 2,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('renders tree nodes and toolbar actions', (tester) async {
    var refreshed = false;
    var ranAll = false;
    var ranFailed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: TestExplorerPanel(
              tree: sampleTree(status: TestNodeStatus.pass),
              onRefresh: () => refreshed = true,
              onRunAll: () => ranAll = true,
              onRunFailed: () => ranFailed = true,
              onRunNode: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Demo WS'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('checkout'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);

    await tester.tap(find.byKey(const Key('test-run-all')));
    await tester.tap(find.byKey(const Key('test-run-failed')));
    await tester.tap(find.byKey(const Key('test-refresh')));
    await tester.pump();
    expect(ranAll, isTrue);
    expect(ranFailed, isTrue);
    expect(refreshed, isTrue);
    expect(find.text('Pay'), findsOneWidget);
    expect(find.byTooltip('Run'), findsWidgets);
  });

  testWidgets('search field invokes filter callback', (tester) async {
    String? filter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: TestExplorerPanel(
              tree: sampleTree(),
              onFilterChanged: (value) => filter = value,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('test-explorer-search')), 'pay');
    expect(filter, 'pay');
  });

  testWidgets('expand and collapse controls toggle tree', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: TestExplorerPanel(tree: sampleTree()),
          ),
        ),
      ),
    );

    expect(find.text('Pay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-collapse-all')));
    await tester.pump();
    expect(find.text('Pay'), findsNothing);

    await tester.tap(find.byKey(const Key('test-expand-all')));
    await tester.pump();
    expect(find.text('Pay'), findsOneWidget);
  });

  testWidgets('status updates render running indicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: TestExplorerPanel(
              tree: sampleTree(status: TestNodeStatus.running),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
