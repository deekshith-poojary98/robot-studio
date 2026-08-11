import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/core/gateway/models/run_failure_info.dart';
import 'package:robot_studio/presentation/execution/execution_page.dart';
import 'package:robot_studio/presentation/execution/failed_tests_panel.dart';
import 'package:robot_studio/presentation/reports/run_details_panel.dart';

void main() {
  test('shouldListFailures skips a clean pass', () {
    ExecutionInfo run({
      required ExecutionStatus status,
      int? exitCode,
      int? failed,
    }) {
      return ExecutionInfo(
        id: 'run',
        workspaceId: 'ws',
        projectId: 'p1',
        environmentId: 'e1',
        projectName: 'Demo',
        suite: 'suite.robot',
        status: status,
        startedAt: DateTime.utc(2026, 7, 19),
        exitCode: exitCode,
        failed: failed,
      );
    }

    expect(
      run(
        status: ExecutionStatus.finished,
        exitCode: 0,
        failed: 0,
      ).shouldListFailures,
      isFalse,
    );
    expect(
      run(
        status: ExecutionStatus.failed,
        exitCode: 1,
        failed: 1,
      ).shouldListFailures,
      isTrue,
    );
  });

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
            status: ExecutionStatus.failed,
            currentRun: null,
            failedTests: const [failure],
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsOneWidget);
    expect(find.text('Jump to Source'), findsOneWidget);
    expect(find.text('Re-run Test'), findsOneWidget);
  });

  testWidgets('Execution page hides Failed Tests skeleton on a passing run', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: const [],
            status: ExecutionStatus.finished,
            currentRun: ExecutionInfo(
              id: 'run-pass',
              workspaceId: 'ws',
              projectId: 'p1',
              environmentId: 'e1',
              projectName: 'Demo',
              suite: 'tests/ok.robot',
              status: ExecutionStatus.finished,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              exitCode: 0,
              failed: 0,
              passed: 1,
              totalTests: 1,
            ),
            isLoadingFailures: true,
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsNothing);
    expect(find.byKey(const ValueKey('failed-tests-skeleton')), findsNothing);
    expect(find.text('Live Output'), findsOneWidget);
  });

  testWidgets('Execution page hides Failed Tests while running', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: [],
            status: ExecutionStatus.running,
            currentRun: null,
            failedTests: [failure],
          ),
        ),
      ),
    );

    expect(find.text('Failed Tests'), findsNothing);
  });

  testWidgets('loading state uses skeleton instead of progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FailedTestsPanel(failures: [], isLoading: true, embedded: true),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('failed-tests-skeleton')), findsOneWidget);
  });

  testWidgets('quiet load hides Failed Tests until ready', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunDetailsPanel(
            run: ExecutionInfo(
              id: 'run-1',
              workspaceId: 'ws',
              projectId: 'p1',
              environmentId: 'e1',
              projectName: 'Checkout',
              suite: 'tests/checkout.robot',
              status: ExecutionStatus.failed,
              startedAt: DateTime.utc(2026, 7, 19, 11, 0, 0),
              failed: 1,
              passed: 0,
              totalTests: 1,
            ),
            failuresReady: false,
            isLoadingFailures: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed Tests'), findsNothing);
    expect(find.byKey(const ValueKey('failed-tests-skeleton')), findsNothing);
  });
}
