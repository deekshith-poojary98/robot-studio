import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:robot_studio/presentation/editor/editor_find_panel.dart';

void main() {
  late CodeLineEditingController editing;
  late CodeFindController finder;

  setUp(() {
    editing = CodeLineEditingController(
      codeLines: CodeLines.fromText('one\ntwo\nthree\nnothing\n'),
    );
    finder = CodeFindController(editing);
  });

  tearDown(() {
    finder.dispose();
    editing.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                const ColoredBox(color: Colors.black, child: SizedBox.expand()),
                ValueListenableBuilder<CodeFindValue?>(
                  valueListenable: finder,
                  builder: (context, value, child) =>
                      EditorFindPanel(controller: finder, readOnly: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder panelBox() => find.byWidgetPredicate(
        (widget) => widget is Container && widget.constraints?.maxWidth == 460,
      );

  test('effectivePattern wraps whole-word queries', () {
    expect(
      EditorFindPanel.effectivePattern(
        'one',
        wholeWord: true,
        regex: false,
      ),
      r'\bone\b',
    );
    expect(
      EditorFindPanel.effectivePattern(
        'a.b',
        wholeWord: true,
        regex: false,
      ),
      r'\ba\.b\b',
    );
    expect(
      EditorFindPanel.effectivePattern(
        'foo|bar',
        wholeWord: true,
        regex: true,
      ),
      r'\b(?:foo|bar)\b',
    );
    expect(
      EditorFindPanel.effectivePattern(
        'one',
        wholeWord: false,
        regex: false,
      ),
      'one',
    );
  });

  testWidgets('find box floats at the top and leaves the document visible', (
    tester,
  ) async {
    finder.findMode();
    await pumpPanel(tester);

    expect(find.text('Find'), findsOneWidget);

    // re_editor stacks the panel over the editor field, so the painted box must
    // stay small instead of expanding across the whole document.
    final box = tester.getRect(panelBox().first);
    expect(box.height, lessThan(60));
    expect(box.top, lessThan(20));
    expect(box.right, lessThan(800));

    expect(
      EditorFindPanel(controller: finder, readOnly: false)
          .preferredSize
          .height,
      lessThan(60),
    );
  });

  testWidgets('replace row appears in replace mode and Esc closes the panel', (
    tester,
  ) async {
    finder.replaceMode();
    await pumpPanel(tester);

    expect(find.text('Replace'), findsOneWidget);
    expect(
      EditorFindPanel(controller: finder, readOnly: false)
          .preferredSize
          .height,
      greaterThan(
        EditorFindPanel(controller: finder, readOnly: true)
            .preferredSize
            .height,
      ),
    );

    finder.findInputFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(finder.value, isNull);
    expect(find.text('Find'), findsNothing);
  });

  testWidgets('match whole word wraps the search pattern', (tester) async {
    finder.findMode();
    await pumpPanel(tester);

    await tester.enterText(find.byType(TextField).first, 'one');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Substring "one" also sits inside "nothing" — without whole-word both match.
    expect(find.text('ab'), findsOneWidget);
    await tester.tap(find.text('ab'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(finder.value?.option.pattern, r'\bone\b');
    expect(finder.value?.option.regex, isTrue);
    // Input still shows the raw query, not the wrapped regex.
    expect(finder.findInputController.text, 'one');
  });
}
