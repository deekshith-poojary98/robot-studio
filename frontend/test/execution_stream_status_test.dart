import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/shell/controllers/execution_shell_controller.dart';

class _FakeGateway implements TransportGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late ExecutionShellController controller;
  var notified = 0;

  setUp(() {
    notified = 0;
    controller = ExecutionShellController(
      gateway: _FakeGateway(),
      notify: () => notified++,
      isMounted: () => true,
      appendLog: (_) {},
      onRunFinished: () async {},
      workspace: () => null,
      backendConnected: () => true,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('ignores historical status events before a run is started', () {
    controller.handleStreamEvent(
      const ExecutionStreamEvent(
        type: 'status',
        runId: 'old-run',
        status: 'failed',
      ),
    );

    expect(controller.executionStatus, ExecutionStatus.idle);
    expect(notified, 0);
  });

  test('applies status events for the active run', () {
    controller.currentExecution = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'proj',
      environmentId: 'env',
      projectName: 'Amazon',
      suite: 'suite.robot',
      status: ExecutionStatus.running,
      startedAt: DateTime.utc(2026, 1, 1),
      finishedAt: null,
      durationMs: null,
      exitCode: null,
      command: 'robot',
      outputDir: null,
      outputXml: null,
      logHtml: null,
      reportHtml: null,
    );
    controller.executionStatus = ExecutionStatus.running;

    controller.handleStreamEvent(
      const ExecutionStreamEvent(
        type: 'status',
        runId: 'run-1',
        status: 'failed',
      ),
    );

    expect(controller.executionStatus, ExecutionStatus.failed);
    expect(notified, 1);
  });

  test('ignores status events for a different run id', () {
    controller.currentExecution = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'proj',
      environmentId: 'env',
      projectName: 'Amazon',
      suite: 'suite.robot',
      status: ExecutionStatus.running,
      startedAt: DateTime.utc(2026, 1, 1),
      finishedAt: null,
      durationMs: null,
      exitCode: null,
      command: 'robot',
      outputDir: null,
      outputXml: null,
      logHtml: null,
      reportHtml: null,
    );
    controller.executionStatus = ExecutionStatus.running;

    controller.handleStreamEvent(
      const ExecutionStreamEvent(
        type: 'status',
        runId: 'other-run',
        status: 'failed',
      ),
    );

    expect(controller.executionStatus, ExecutionStatus.running);
    expect(notified, 0);
  });

  test('aborted events stop the timer and clear live progress', () {
    controller.currentExecution = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'proj',
      environmentId: 'env',
      projectName: 'Amazon',
      suite: 'suite.robot',
      status: ExecutionStatus.running,
      startedAt: DateTime.utc(2026, 1, 1),
      finishedAt: null,
      durationMs: null,
      exitCode: null,
      command: 'robot',
      outputDir: null,
      outputXml: null,
      logHtml: null,
      reportHtml: null,
    );
    controller.executionStatus = ExecutionStatus.running;
    controller.liveSuite = 'suite.robot';
    controller.liveTest = 'Example Test';
    controller.startElapsedTimer();

    controller.handleStreamEvent(
      const ExecutionStreamEvent(
        type: 'aborted',
        runId: 'run-1',
        status: 'aborted',
        message: 'Robot Framework is not installed',
      ),
    );

    expect(controller.executionStatus, ExecutionStatus.aborted);
    expect(controller.liveSuite, isEmpty);
    expect(controller.liveTest, isEmpty);
    expect(controller.elapsedTimer, isNull);
  });

  test('batches output lines instead of notifying per line', () async {
    controller.currentExecution = ExecutionInfo(
      id: 'run-1',
      workspaceId: 'ws',
      projectId: 'proj',
      environmentId: 'env',
      projectName: 'Amazon',
      suite: 'suite.robot',
      status: ExecutionStatus.running,
      startedAt: DateTime.utc(2026, 1, 1),
      finishedAt: null,
      durationMs: null,
      exitCode: null,
      command: 'robot',
      outputDir: null,
      outputXml: null,
      logHtml: null,
      reportHtml: null,
    );
    controller.executionStatus = ExecutionStatus.running;

    for (var i = 0; i < 20; i++) {
      controller.handleStreamEvent(
        ExecutionStreamEvent(type: 'output', runId: 'run-1', line: 'line-$i'),
      );
    }
    expect(notified, 0);
    expect(controller.executionLines, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(notified, 1);
    expect(controller.executionLines.length, 20);
  });

  test('resetForWorkspaceChange clears console and run chrome', () {
    controller.executionLines = ['old-line'];
    controller.executionHistory = [
      ExecutionInfo(
        id: 'run-1',
        workspaceId: 'ws',
        projectId: 'proj',
        environmentId: 'env',
        projectName: 'Old',
        suite: 'suite.robot',
        status: ExecutionStatus.finished,
        startedAt: DateTime.utc(2026, 1, 1),
        finishedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
        durationMs: 1000,
        exitCode: 0,
        command: 'robot',
        outputDir: null,
        outputXml: null,
        logHtml: null,
        reportHtml: null,
      ),
    ];
    controller.currentExecution = controller.executionHistory.first;
    controller.executionStatus = ExecutionStatus.finished;
    controller.failedTests = [
      const RunTestFailureInfo(
        runId: 'run-1',
        name: 'Failing test',
        message: 'boom',
        source: '/tmp/suite.robot',
        line: 10,
      ),
    ];
    controller.liveSuite = 'suite.robot';
    controller.liveTest = 'Failing test';

    controller.resetForWorkspaceChange();

    expect(controller.executionLines, isEmpty);
    expect(controller.executionHistory, isEmpty);
    expect(controller.currentExecution, isNull);
    expect(controller.executionStatus, ExecutionStatus.idle);
    expect(controller.failedTests, isEmpty);
    expect(controller.liveSuite, isEmpty);
    expect(controller.liveTest, isEmpty);
  });
}
