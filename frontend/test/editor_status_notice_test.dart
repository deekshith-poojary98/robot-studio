import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/editor/editor_page.dart';
import 'package:robot_studio/presentation/shell/controllers/editor_shell_controller.dart';

class _FakeGateway implements TransportGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late EditorShellController controller;
  var notified = 0;

  setUp(() {
    notified = 0;
    controller = EditorShellController(
      gateway: _FakeGateway(),
      notify: () => notified++,
      isMounted: () => true,
      workspace: () => null,
    );
  });

  tearDown(() => controller.dispose());

  test('status notice expires instead of sticking above the editor', () async {
    controller.setStatusMessage(
      'Saved login.robot',
      ttl: const Duration(milliseconds: 20),
    );
    expect(controller.statusMessage, 'Saved login.robot');
    expect(notified, 0, reason: 'callers set it inside their own setState');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.statusMessage, isNull);
    expect(notified, 1);
  });

  test('a newer notice replaces the pending expiry', () async {
    controller.setStatusMessage(
      'Copied relative path',
      ttl: const Duration(milliseconds: 20),
    );
    controller.setStatusMessage(
      'Copied absolute path',
      ttl: const Duration(milliseconds: 80),
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(controller.statusMessage, 'Copied absolute path');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.statusMessage, isNull);
  });

  test('clearing cancels the pending expiry', () async {
    controller.setStatusMessage(
      'Formatted document',
      ttl: const Duration(milliseconds: 20),
    );
    controller.setStatusMessage(null);
    expect(controller.statusMessage, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(notified, 0);
  });

  testWidgets('editor notice can be dismissed early', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPage(
            tabs: const [],
            activePath: null,
            wordWrap: true,
            hover: null,
            references: const [],
            statusMessage: 'Saved login.robot',
            onDismissStatusMessage: () => dismissed++,
            breadcrumb: const EditorBreadcrumbInfo(),
            completionItems: const [],
            diagnostics: const [],
            hoverTooltip: null,
            peekDefinition: null,
            onSelectTab: (_) {},
            onCloseTab: (_) {},
            onContentChanged: (_, _) {},
            onSave: () {},
            onHoverRequest: (_, _) {},
            onHoverExit: () {},
            onCtrlClick: () {},
            onClosePeek: () {},
            onCursorChanged: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Saved login.robot'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, 1);
  });
}
