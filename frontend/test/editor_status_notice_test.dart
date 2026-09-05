import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/editor/editor_page.dart';
import 'package:robot_studio/presentation/editor/robot_code_editor.dart';
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

  test('onContentChanged skips notify when text is unchanged', () {
    controller.tabs = [
      EditorTabInfo(
        path: '/tmp/demo.robot',
        content: 'Hello',
        savedContent: 'Hello',
        mtime: 1,
      ),
    ];
    controller.activePath = '/tmp/demo.robot';

    controller.onContentChanged('/tmp/demo.robot', 'Hello');
    expect(notified, 0);

    controller.onContentChanged('/tmp/demo.robot', 'Hello!');
    expect(notified, 1);
    expect(controller.tabs.first.content, 'Hello!');
  });

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

  test(
    'switching tabs drops peek and hover leftover from the previous file',
    () {
      controller.peekDefinition = const IndexedSymbolInfo(
        id: 'v1',
        name: 'AUT_URL',
        kind: SymbolKind.variable,
        filePath: '/ws/data.py',
        line: 1,
      );
      controller.hoverTooltip = const SignatureHelpInfo(keyword: 'Input Text');
      controller.completionItems = const [
        CompletionItemInfo(label: 'Click Element', kind: 'keyword'),
      ];

      controller.onActiveTabChanged();

      expect(controller.peekDefinition, isNull);
      expect(controller.hoverTooltip, isNull);
      expect(controller.completionItems, isEmpty);
    },
  );

  test('clearActiveDocument drops the outline tree, not just the flat list', () {
    // Outline renders from documentAnalysis; clearing only documentOutline left
    // the last file's tree on screen after every tab was closed.
    controller.documentAnalysis = DocumentAnalysisInfo(
      filePath: '/ws/login.robot',
      root: const DocumentSymbolNode(
        id: 'suite:login',
        name: 'login',
        kind: SymbolKind.testSuite,
        line: 1,
      ),
      foldingRanges: const [FoldingRangeInfo(startLine: 1, endLine: 4)],
    );
    controller.documentOutline = const [
      IndexedSymbolInfo(
        id: 'k1',
        name: 'Login',
        kind: SymbolKind.keyword,
        filePath: '/ws/login.robot',
        line: 2,
      ),
    ];
    controller.activePath = '/ws/login.robot';
    controller.selectedOutlineSymbol = controller.documentOutline.first;
    controller.activeDocumentSymbol = controller.documentAnalysis!.root;
    controller.diagnostics = const [];
    controller.cursorLine = 12;

    controller.clearActiveDocument();

    expect(controller.documentAnalysis, isNull);
    expect(controller.documentOutline, isEmpty);
    expect(controller.activePath, isNull);
    expect(controller.selectedOutlineSymbol, isNull);
    expect(controller.activeDocumentSymbol, isNull);
    expect(controller.loadingOutline, isFalse);
    expect(controller.cursorLine, 1);
  });

  test('onViewportChanged stores offsets without notify', () {
    controller.tabs = [
      EditorTabInfo(
        path: '/tmp/demo.robot',
        content: 'Hello',
        savedContent: 'Hello',
        mtime: 1,
      ),
    ];

    controller.onViewportChanged('/tmp/demo.robot', 12, 80);

    expect(controller.tabs.first.scrollOffsetX, 12);
    expect(controller.tabs.first.scrollOffsetY, 80);
    expect(notified, 0);
  });

  test('restoreCaretFromTab copies the tab caret into the shell', () {
    controller.tabs = [
      EditorTabInfo(
        path: '/tmp/demo.robot',
        content: 'Hello',
        savedContent: 'Hello',
        mtime: 1,
        cursorLine: 18,
        cursorColumn: 4,
      ),
    ];

    controller.restoreCaretFromTab('/tmp/demo.robot');

    expect(controller.cursorLine, 18);
    expect(controller.cursorColumn, 4);
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

  testWidgets('switching the active tab remounts the editor on the new file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final data = EditorTabInfo(
      path: '/ws/data.py',
      content: 'AUT_URL = "https://example.test"\n',
      savedContent: 'AUT_URL = "https://example.test"\n',
      mtime: 1,
    );
    final actions = EditorTabInfo(
      path: '/ws/helper/actions.robot',
      content: '*** Settings ***\nLibrary    Browser\n',
      savedContent: '*** Settings ***\nLibrary    Browser\n',
      mtime: 1,
    );

    Widget page(String activePath) {
      return MaterialApp(
        home: Scaffold(
          body: EditorPage(
            tabs: [data, actions],
            activePath: activePath,
            wordWrap: true,
            hover: null,
            references: const [],
            statusMessage: null,
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
      );
    }

    await tester.pumpWidget(page(data.path));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(data.path)), findsOneWidget);

    await tester.pumpWidget(page(actions.path));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(data.path)), findsNothing);
    expect(find.byKey(ValueKey(actions.path)), findsOneWidget);
  });

  testWidgets('switching tabs restores the previous scroll offset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final long = List.generate(80, (i) => 'Line $i of the suite').join('\n');
    final first = EditorTabInfo(
      path: '/ws/long.robot',
      content: long,
      savedContent: long,
      mtime: 1,
    );
    final second = EditorTabInfo(
      path: '/ws/short.robot',
      content: '*** Settings ***\n',
      savedContent: '*** Settings ***\n',
      mtime: 1,
    );
    var activePath = first.path;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return EditorPage(
                tabs: [first, second],
                activePath: activePath,
                wordWrap: true,
                hover: null,
                references: const [],
                statusMessage: null,
                breadcrumb: const EditorBreadcrumbInfo(),
                completionItems: const [],
                diagnostics: const [],
                hoverTooltip: null,
                peekDefinition: null,
                onSelectTab: (path) => setState(() => activePath = path),
                onCloseTab: (_) {},
                onContentChanged: (_, _) {},
                onSave: () {},
                onHoverRequest: (_, _) {},
                onHoverExit: () {},
                onCtrlClick: () {},
                onClosePeek: () {},
                onCursorChanged: (_, _) {},
                onViewportChanged: (path, x, y) {
                  final tab = path == first.path ? first : second;
                  tab.scrollOffsetX = x;
                  tab.scrollOffsetY = y;
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.state<RobotCodeEditorState>(
      find.byType(RobotCodeEditor),
    );
    editor.debugJumpVerticalScroll(240);
    await tester.pumpAndSettle();
    final scrolled = editor.debugVerticalScrollOffset;
    expect(scrolled, greaterThan(50));

    await tester.tap(find.text(second.fileName));
    await tester.pumpAndSettle();
    expect(first.scrollOffsetY, closeTo(scrolled, 1));
    expect(find.byKey(ValueKey(second.path)), findsOneWidget);

    await tester.tap(find.text(first.fileName));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(first.path)), findsOneWidget);
    final restored = tester.state<RobotCodeEditorState>(
      find.byType(RobotCodeEditor),
    );
    expect(restored.debugVerticalScrollOffset, closeTo(scrolled, 1));
  });
}
