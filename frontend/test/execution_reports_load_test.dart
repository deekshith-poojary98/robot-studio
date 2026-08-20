import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/report_info.dart';
import 'package:robot_studio/core/gateway/models/workspace_info.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/shell/controllers/execution_shell_controller.dart';

class _ReportsGateway implements TransportGateway {
  _ReportsGateway({
    required this.runs,
    required this.dashboard,
    this.dashboardHold,
  });

  final List<ExecutionInfo> runs;
  final DashboardSummary dashboard;
  final Completer<DashboardSummary>? dashboardHold;

  @override
  Future<List<ExecutionInfo>> listReports() async {
    return runs;
  }

  @override
  Future<DashboardSummary> getReportsDashboard() {
    final hold = dashboardHold;
    if (hold != null) return hold.future;
    return Future<DashboardSummary>.value(dashboard);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ExecutionInfo _run(String id) {
  return ExecutionInfo(
    id: id,
    workspaceId: 'ws',
    projectId: 'p1',
    environmentId: 'e1',
    projectName: 'Demo',
    suite: 'tests/demo.robot',
    status: ExecutionStatus.finished,
    startedAt: DateTime.utc(2026, 7, 19, 10, 0, 0),
  );
}

void main() {
  final workspace = WorkspaceInfo(
    id: 'ws',
    name: 'demo',
    path: '/tmp/demo',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  ExecutionShellController controllerFor(_ReportsGateway gateway) {
    return ExecutionShellController(
      gateway: gateway,
      notify: () {},
      isMounted: () => true,
      appendLog: (_) {},
      onRunFinished: () async {},
      workspace: () => workspace,
      backendConnected: () => true,
    );
  }

  test('auto-selects the latest run as soon as the list returns', () async {
    final hold = Completer<DashboardSummary>();
    final latest = _run('run-latest');
    final gateway = _ReportsGateway(
      runs: [latest, _run('run-older')],
      dashboard: DashboardSummary(totalRuns: 2, lastRun: latest),
      dashboardHold: hold,
    );
    final controller = controllerFor(gateway);
    addTearDown(controller.dispose);

    final pending = controller.loadReports();
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedReport?.id, 'run-latest');
    expect(controller.loadingReports, isFalse);
    expect(controller.loadingDashboard, isTrue);

    hold.complete(gateway.dashboard);
    await pending;
    expect(controller.loadingDashboard, isFalse);
  });

  test(
    'keeps a cached run visible instead of showing a loading spinner',
    () async {
      final hold = Completer<DashboardSummary>();
      final cached = _run('run-cached');
      final gateway = _ReportsGateway(
        runs: [cached],
        dashboard: const DashboardSummary(totalRuns: 1),
        dashboardHold: hold,
      );
      final controller = controllerFor(gateway);
      addTearDown(controller.dispose);
      controller.reportRuns = [cached];
      controller.selectedReport = cached;

      final pending = controller.loadReports();
      expect(controller.loadingReports, isFalse);
      expect(controller.selectedReport?.id, 'run-cached');

      hold.complete(gateway.dashboard);
      await pending;
    },
  );
}
