import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:robot_studio/core/gateway/models/index_info.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/editor/editor_run_gutter.dart';

void main() {
  DocumentSymbolNode suiteOutline() {
    return const DocumentSymbolNode(
      id: 'suite:login.robot',
      name: 'login.robot',
      kind: SymbolKind.testSuite,
      line: 1,
      endLine: 40,
      children: [
        DocumentSymbolNode(
          id: 'section:keywords',
          name: '*** Keywords ***',
          kind: SymbolKind.section,
          line: 8,
          endLine: 16,
          children: [
            DocumentSymbolNode(
              id: 'keyword:Open Browser',
              name: 'Open Browser To Login Page',
              kind: SymbolKind.keyword,
              line: 10,
              endLine: 16,
            ),
          ],
        ),
        DocumentSymbolNode(
          id: 'section:tests',
          name: '*** Test Cases ***',
          kind: SymbolKind.section,
          line: 18,
          endLine: 40,
          children: [
            DocumentSymbolNode(
              id: 'test:Valid Login',
              name: 'Valid Login',
              kind: SymbolKind.testCase,
              line: 20,
              endLine: 28,
            ),
            DocumentSymbolNode(
              id: 'test:Invalid Password',
              name: 'Invalid Password',
              kind: SymbolKind.testCase,
              line: 30,
              endLine: 40,
            ),
          ],
        ),
      ],
    );
  }

  group('runnableTestsFromOutline', () {
    test('keeps Robot test cases and drops keywords', () {
      final tests = runnableTestsFromOutline(
        suiteOutline(),
        filePath: '/proj/tests/login.robot',
      );
      expect(tests.map((t) => t.name).toList(), [
        'Valid Login',
        'Invalid Password',
      ]);
      expect(tests.first.line, 20);
      expect(tests.first.endLine, 28);
    });

    test('is empty for resource files, Python, and missing outlines', () {
      final root = suiteOutline();
      expect(
        runnableTestsFromOutline(
          root,
          filePath: '/proj/resources/login.resource',
        ),
        isEmpty,
      );
      expect(
        runnableTestsFromOutline(root, filePath: '/proj/libs/login.py'),
        isEmpty,
      );
      expect(
        runnableTestsFromOutline(null, filePath: '/proj/tests/login.robot'),
        isEmpty,
      );
    });
  });

  group('enclosingRunnableTest', () {
    test('matches the caret on the header and inside the body', () {
      final tests = runnableTestsFromOutline(
        suiteOutline(),
        filePath: 'login.robot',
      );
      expect(enclosingRunnableTest(tests, 20)?.name, 'Valid Login');
      expect(enclosingRunnableTest(tests, 24)?.name, 'Valid Login');
      expect(enclosingRunnableTest(tests, 30)?.name, 'Invalid Password');
      expect(enclosingRunnableTest(tests, 12), isNull);
    });

    test('prefers the inner test when ranges nest', () {
      const tests = [
        EditorRunnableTest(line: 10, endLine: 40, name: 'Outer'),
        EditorRunnableTest(line: 20, endLine: 30, name: 'Inner'),
      ];
      expect(enclosingRunnableTest(tests, 25)?.name, 'Inner');
    });
  });

  testWidgets('gutter play control runs the test on that line', (tester) async {
    EditorRunnableTest? launched;
    final notifier = ValueNotifier<CodeIndicatorValue?>(
      CodeIndicatorValue(
        paragraphs: [
          CodeLineRenderParagraph(
            index: 19,
            paragraph: _FakeParagraph(),
            offset: Offset.zero,
            chunkParent: false,
            chunkLongText: false,
          ),
          CodeLineRenderParagraph(
            index: 21,
            paragraph: _FakeParagraph(),
            offset: const Offset(0, 20),
            chunkParent: false,
            chunkLongText: false,
          ),
        ],
      ),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 80,
            child: RobotTestRunGutter(
              notifier: notifier,
              tests: const [
                EditorRunnableTest(line: 20, endLine: 28, name: 'Valid Login'),
              ],
              onRun: (test) => launched = test,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('run-test-gutter-20')), findsOneWidget);
    expect(find.byKey(const Key('run-test-gutter-22')), findsNothing);

    await tester.tap(find.byKey(const Key('run-test-gutter-20')));
    await tester.pump();
    expect(launched?.name, 'Valid Login');
  });

  testWidgets('gutter play control is inert while a run is in progress', (
    tester,
  ) async {
    var taps = 0;
    final notifier = ValueNotifier<CodeIndicatorValue?>(
      CodeIndicatorValue(
        paragraphs: [
          CodeLineRenderParagraph(
            index: 19,
            paragraph: _FakeParagraph(),
            offset: Offset.zero,
            chunkParent: false,
            chunkLongText: false,
          ),
        ],
      ),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 40,
            child: RobotTestRunGutter(
              notifier: notifier,
              tests: const [
                EditorRunnableTest(line: 20, endLine: 28, name: 'Valid Login'),
              ],
              enabled: false,
              onRun: (_) => taps++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('run-test-gutter-20')));
    await tester.pump();
    expect(taps, 0);
  });
}

class _FakeParagraph implements IParagraph {
  @override
  double get width => 80;

  @override
  double get height => 18;

  @override
  double get preferredLineHeight => 18;

  @override
  bool get trucated => false;

  @override
  int get length => 1;

  @override
  int get lineCount => 1;

  @override
  void draw(Canvas canvas, Offset offset) {}

  @override
  TextPosition getPosition(Offset offset) => const TextPosition(offset: 0);

  @override
  TextRange getWord(Offset offset) => TextRange.empty;

  @override
  InlineSpan? getSpanForPosition(TextPosition position) => null;

  @override
  TextRange getRangeForSpan(InlineSpan span) => TextRange.empty;

  @override
  TextRange getLineBoundary(TextPosition position) => TextRange.empty;

  @override
  Offset? getOffset(TextPosition position) => Offset.zero;

  @override
  List<Rect> getRangeRects(TextRange range) => const [];
}
