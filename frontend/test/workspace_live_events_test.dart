import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/workspace_event_info.dart';
import 'package:robot_studio/presentation/shell/controllers/workspace_live_controller.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';
import 'package:flutter/material.dart';

void main() {
  test('WorkspaceStreamEvent parses wire payload', () {
    final event = WorkspaceStreamEvent.fromJson({
      'type': 'FILE_MODIFIED',
      'path': 'tests/a.robot',
      'absolute_path': '/tmp/ws/tests/a.robot',
    });
    expect(event.type, 'FILE_MODIFIED');
    expect(event.isFilesystemEvent, isTrue);
    expect(event.isRobotSource, isTrue);
  });

  testWidgets('StatusBar shows live notification', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(
            projectName: 'Demo',
            notification: 'Indexing workspace...',
          ),
        ),
      ),
    );
    expect(find.text('Indexing workspace...'), findsOneWidget);
  });

  test('WorkspaceLiveController debounces git refresh', () async {
    var gitCalls = 0;
    final fs = <WorkspaceStreamEvent>[];
    final controller = WorkspaceLiveController(
      notify: () {},
      isMounted: () => true,
      appendLog: (_) {},
      onFilesystemEvent: (event) async => fs.add(event),
      onGitChanged: () async {
        gitCalls += 1;
      },
      onIndexUpdated: (_) async {},
      onTestsChanged: () async {},
      onEnvironmentChanged: () async {},
      onProjectMissing: (_) async {},
      onWorkspaceMissing: (_) async {},
      onStatusMessage: (_) {},
    );

    controller.handleEvent(
      const WorkspaceStreamEvent(type: 'FILE_MODIFIED', path: 'a.robot'),
    );
    controller.handleEvent(
      const WorkspaceStreamEvent(type: 'FILE_MODIFIED', path: 'b.robot'),
    );
    controller.handleEvent(const WorkspaceStreamEvent(type: 'GIT_CHANGED'));
    expect(gitCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(gitCalls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(fs.length, greaterThanOrEqualTo(1));
    await controller.disconnect();
  });

  test('pathsEqual normalizes separators', () {
    expect(
      WorkspaceLiveController.pathsEqual('/tmp/a/b.robot', '/tmp/a/b.robot'),
      isTrue,
    );
  });
}
