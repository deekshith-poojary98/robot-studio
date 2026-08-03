import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/gateway/models/run_failure_info.dart';
import 'package:robot_studio/presentation/execution/execution_page.dart';
import 'package:robot_studio/presentation/execution/failed_tests_panel.dart';

void main() {
  const failure = RunTestFailureInfo(
    runId: 'run-1',
    name: 'Broken Login',
    message: 'Expected and actual did not match',
    source: '/proj/tests/failing.robot',
    line: 5,
  );

  testWidgets('Failed Tests panel exposes Jump and Re-run', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var jumped = false;
    var rerun = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FailedTestsPanel(
            failures: const [failure],
            onJumpToSource: (_) => jumped = true,
            onRerunTest: (_) => rerun = true,
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsOneWidget);
    expect(find.text('Broken Login'), findsOneWidget);
    expect(find.textContaining('did not match'), findsOneWidget);

    await tester.tap(find.text('Jump to Source'));
    await tester.pump();
    expect(jumped, isTrue);

    await tester.tap(find.text('Re-run Test'));
    await tester.pump();
    expect(rerun, isTrue);
  });

  testWidgets('Execution page shows Failed Tests after a finished run', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: const [],
            history: const [],
            isLoadingHistory: false,
            status: ExecutionStatus.failed,
            currentRun: null,
            elapsedLabel: '1.2s',
            failedTests: const [failure],
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsOneWidget);
    expect(find.text('Jump to Source'), findsOneWidget);
    expect(find.text('Re-run Test'), findsOneWidget);
  });

  testWidgets('Execution page hides Failed Tests while running', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: [],
            history: [],
            isLoadingHistory: false,
            status: ExecutionStatus.running,
            currentRun: null,
            elapsedLabel: '0.5s',
            failedTests: [failure],
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsNothing);
  });
}
