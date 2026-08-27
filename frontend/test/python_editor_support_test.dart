import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/editor/editor_language_widgets.dart';
import 'package:robot_studio/presentation/editor/editor_syntax.dart';
import 'package:robot_studio/presentation/shell/controllers/editor_shell_controller.dart';

/// Returns per-file results after a caller-controlled delay, so a slow reply
/// can be made to land after a newer request has already completed.
class _SlowLanguageGateway implements TransportGateway {
  _SlowLanguageGateway();

  final Map<String, Duration> delays = {};
  final List<String> completionCalls = [];

  @override
  Future<List<CompletionItemInfo>> languageCompletion({
    required String filePath,
    required int line,
    required int column,
    required String content,
    String query = '',
  }) async {
    completionCalls.add(content);
    await Future<void>.delayed(delays[content] ?? Duration.zero);
    return [
      CompletionItemInfo(
        label: content,
        kind: 'variable',
        provider: 'python_jedi',
        insertText: content,
      ),
    ];
  }

  @override
  Future<List<DiagnosticInfo>> languageDiagnostics({
    required String filePath,
    required String content,
  }) async {
    await Future<void>.delayed(delays[content] ?? Duration.zero);
    return [
      DiagnosticInfo(
        severity: DiagnosticSeverity.error,
        filePath: filePath,
        line: 1,
        column: 1,
        message: content,
        source: 'pyflakes',
      ),
    ];
  }

  @override
  Future<SignatureHelpInfo?> languageSignatureHelp({
    required String filePath,
    required int line,
    required int column,
    required String content,
    bool hover = false,
  }) async {
    await Future<void>.delayed(delays[content] ?? Duration.zero);
    return null;
  }

  @override
  Future<DocumentAnalysisInfo> analyzeDocument({
    required String filePath,
    required String content,
  }) async {
    return DocumentAnalysisInfo(
      filePath: filePath,
      root: DocumentSymbolNode(
        id: 'file:1',
        name: filePath,
        kind: SymbolKind.file,
        line: 1,
        endLine: 99,
      ),
      foldingRanges: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('python file gating', () {
    test('stub and script variants get language features', () {
      expect(isPythonPath('lib/client.py'), isTrue);
      expect(isPythonPath('lib/client.pyi'), isTrue);
      expect(isPythonPath('lib/tool.PYW'), isTrue);
      expect(isPythonPath('suite.robot'), isFalse);

      // Both languages are analysable; unrelated files are not.
      expect(isSourcePath('suite.resource'), isTrue);
      expect(isSourcePath('notes.md'), isFalse);

      expect(EditorShellController.isPythonPath('a.pyi'), isTrue);
      expect(EditorShellController.isRobotPath('a.pyi'), isFalse);
    });
  });

  group('python suite indent', () {
    test('a trailing colon opens an indented block', () {
      expect(opensPythonSuite('def f():', 8), isTrue);
      expect(opensPythonSuite('class A:', 8), isTrue);
      expect(opensPythonSuite('    if x:', 9), isTrue);
      expect(opensPythonSuite('for i in items:', 15), isTrue);
    });

    test('a colon in a comment or elsewhere does not', () {
      expect(opensPythonSuite('x = 1', 5), isFalse);
      expect(opensPythonSuite('d = {1: 2}', 10), isFalse);
      expect(opensPythonSuite('value: int = 3', 14), isFalse);
      // The colon is commented out, so no suite is opened.
      expect(opensPythonSuite('x = 1  # note:', 14), isFalse);
      // ...but a real suite with a trailing comment still indents.
      expect(opensPythonSuite('if x:  # note', 13), isTrue);
    });

    test('only text before the caret counts', () {
      // Caret sits before the colon, so Enter splits above the suite header.
      expect(opensPythonSuite('def f():', 4), isFalse);
    });
  });

  group('language refresh staleness', () {
    late _SlowLanguageGateway gateway;
    late EditorShellController controller;

    setUp(() {
      gateway = _SlowLanguageGateway();
      controller = EditorShellController(
        gateway: gateway,
        notify: () {},
        isMounted: () => true,
        workspace: () => WorkspaceInfo(
          id: 'w1',
          name: 'ws',
          path: '/ws',
          createdAt: DateTime(2026),
        ),
      );
    });

    tearDown(() => controller.dispose());

    test('a slow earlier reply never overwrites the newest one', () async {
      final tab = EditorTabInfo(
        path: '/ws/module.py',
        content: 'old',
        savedContent: 'old',
        mtime: 0,
      );
      controller.tabs = [tab];
      controller.activePath = tab.path;

      gateway.delays['old'] = const Duration(milliseconds: 120);
      gateway.delays['new'] = Duration.zero;

      final stale = controller.refreshLanguageFeatures();
      tab.content = 'new';
      final fresh = controller.refreshLanguageFeatures();
      await Future.wait([stale, fresh]);

      expect(gateway.completionCalls, ['old', 'new']);
      expect(
        controller.completionItems.single.label,
        'new',
        reason: 'the reply for the older buffer must be discarded',
      );
      expect(controller.diagnostics.single.message, 'new');
    });

    test('python files receive diagnostics and feed the problems panel', () async {
      final tab = EditorTabInfo(
        path: '/ws/module.py',
        content: 'import os',
        savedContent: 'import os',
        mtime: 0,
      );
      controller.tabs = [tab];
      controller.activePath = tab.path;

      await controller.refreshLanguageFeatures();

      expect(controller.diagnostics, hasLength(1));
      expect(controller.diagnostics.single.source, 'pyflakes');
      expect(
        controller.workspaceProblems.map((item) => item.filePath),
        ['/ws/module.py'],
      );
    });
  });

  group('autocomplete popup lifetime', () {
    testWidgets('leaving the overlay reports a dismissal', (tester) async {
      // Tab only accepts a completion while a popup is on screen, and the popup
      // lives in an overlay the editor does not own — so this signal is what
      // keeps Tab from swallowing an indent after the list closes.
      var dismissals = 0;
      final notifier = ValueNotifier(
        const CodeAutocompleteEditingValue(
          input: 'imp',
          prompts: [CodeFieldPrompt(word: 'import', type: 'keyword')],
          index: 0,
        ),
      );
      addTearDown(notifier.dispose);

      Widget host({required bool showPopup}) => MaterialApp(
        home: showPopup
            ? RobotAutocompleteListView(
                notifier: notifier,
                onSelected: (_) {},
                onDismissed: () => dismissals++,
              )
            : const SizedBox.shrink(),
      );

      await tester.pumpWidget(host(showPopup: true));
      expect(dismissals, 0);

      await tester.pumpWidget(host(showPopup: false));
      expect(dismissals, 1);
    });
  });

  group('outline caret tracking', () {
    test('python scopes are followed like robot keywords', () {
      final controller = EditorShellController(
        gateway: _SlowLanguageGateway(),
        notify: () {},
        isMounted: () => true,
        workspace: () => null,
      );
      addTearDown(controller.dispose);

      controller.documentAnalysis = DocumentAnalysisInfo(
        filePath: '/ws/module.py',
        root: DocumentSymbolNode(
          id: 'file:1',
          name: 'module.py',
          kind: SymbolKind.file,
          line: 1,
          endLine: 20,
          children: [
            DocumentSymbolNode(
              id: 'class:1',
              name: 'Client',
              kind: SymbolKind.classKind,
              line: 1,
              endLine: 20,
              children: [
                DocumentSymbolNode(
                  id: 'method:5',
                  name: 'fetch',
                  kind: SymbolKind.method,
                  line: 5,
                  endLine: 9,
                ),
              ],
            ),
          ],
        ),
        foldingRanges: const [],
      );

      controller.syncActiveSymbol(7);
      expect(controller.activeDocumentSymbol?.name, 'fetch');
      expect(controller.selectedOutlineSymbol?.name, 'fetch');
    });
  });
}
