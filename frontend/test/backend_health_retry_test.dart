import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/shell/controllers/workspace_shell_controller.dart';

class _ControllableHealthGateway implements TransportGateway {
  bool healthy = false;
  int healthCalls = 0;

  @override
  Future<HealthResponse> health() async {
    healthCalls++;
    if (!healthy) {
      throw Exception('backend down');
    }
    return const HealthResponse(
      status: 'ok',
      version: '0.1.0',
      modules: ['workspace'],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('retries every 2s while offline then every 5s while connected', () {
    fakeAsync((async) {
      final gateway = _ControllableHealthGateway();
      var connectedCalls = 0;
      final controller = WorkspaceShellController(
        gateway: gateway,
        notify: () {},
        isMounted: () => true,
        appendLog: (_) {},
        healthOfflineInterval: const Duration(seconds: 2),
        healthConnectedInterval: const Duration(seconds: 5),
      );

      controller.startBackendMonitoring(
        onConnected: () async {
          connectedCalls++;
        },
      );
      async.flushMicrotasks();

      expect(controller.backendStatus, 'offline');
      expect(connectedCalls, 0);
      expect(gateway.healthCalls, 1);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(gateway.healthCalls, 2);

      // Connected interval should not fire while offline.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(gateway.healthCalls, 3);

      gateway.healthy = true;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(connectedCalls, 1);
      expect(gateway.healthCalls, 4);

      // Still on the connected cadence — 2s is not enough.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(gateway.healthCalls, 4);

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(gateway.healthCalls, 5);
      expect(controller.backendStatus, 'connected');

      controller.dispose();
    });
  });

  test('ignores a single transient health failure while connected', () {
    fakeAsync((async) {
      final gateway = _ControllableHealthGateway()..healthy = true;
      var disconnectedCalls = 0;
      final controller = WorkspaceShellController(
        gateway: gateway,
        notify: () {},
        isMounted: () => true,
        appendLog: (_) {},
        healthOfflineInterval: const Duration(seconds: 2),
        healthConnectedInterval: const Duration(seconds: 5),
        offlineFailureThreshold: 3,
      );

      controller.startBackendMonitoring(
        onConnected: () async {},
        onDisconnected: () async {
          disconnectedCalls++;
        },
      );
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');

      gateway.healthy = false;
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(disconnectedCalls, 0);

      gateway.healthy = true;
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(disconnectedCalls, 0);

      controller.dispose();
    });
  });

  test('marks offline after consecutive failures then reconnects', () {
    fakeAsync((async) {
      final gateway = _ControllableHealthGateway()..healthy = true;
      var connectedCalls = 0;
      var disconnectedCalls = 0;
      final controller = WorkspaceShellController(
        gateway: gateway,
        notify: () {},
        isMounted: () => true,
        appendLog: (_) {},
        healthOfflineInterval: const Duration(seconds: 2),
        healthConnectedInterval: const Duration(seconds: 5),
        offlineFailureThreshold: 3,
      );

      controller.startBackendMonitoring(
        onConnected: () async {
          connectedCalls++;
        },
        onDisconnected: () async {
          disconnectedCalls++;
        },
      );
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(connectedCalls, 1);

      gateway.healthy = false;
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(disconnectedCalls, 0);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(disconnectedCalls, 0);

      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'offline');
      expect(disconnectedCalls, 1);

      gateway.healthy = true;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(controller.backendStatus, 'connected');
      expect(connectedCalls, 2);

      controller.dispose();
    });
  });

  test('stops polling on dispose', () {
    fakeAsync((async) {
      final gateway = _ControllableHealthGateway();
      final controller = WorkspaceShellController(
        gateway: gateway,
        notify: () {},
        isMounted: () => true,
        appendLog: (_) {},
        healthOfflineInterval: const Duration(seconds: 1),
        healthConnectedInterval: const Duration(seconds: 1),
      );

      controller.startBackendMonitoring(onConnected: () async {});
      async.flushMicrotasks();
      expect(gateway.healthCalls, 1);

      controller.dispose();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(gateway.healthCalls, 1);
    });
  });
}
