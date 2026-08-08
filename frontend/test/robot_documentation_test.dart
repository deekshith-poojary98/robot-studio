import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/widgets/robot_documentation.dart';

Future<void> _pump(
  WidgetTester tester,
  String documentation, {
  RobotDocFormat format = RobotDocFormat.auto,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: RobotDocumentation(
              documentation: documentation,
              format: format,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _rendered(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .join('\n');

/// Walks every span, including wrappers that only carry children.
///
/// [InlineSpan.visitChildren] skips spans whose `text` is null, which is
/// exactly how bold/italic runs are built here.
void _walk(InlineSpan span, void Function(TextSpan span) visit) {
  if (span is! TextSpan) return;
  visit(span);
  for (final child in span.children ?? const <InlineSpan>[]) {
    _walk(child, visit);
  }
}

/// Plain text of every span in [finder] whose own style satisfies [matches].
List<String> _styledRuns(
  WidgetTester tester,
  Finder finder,
  bool Function(TextStyle style) matches,
) {
  final runs = <String>[];
  for (final widget in tester.widgetList<SelectableText>(finder)) {
    final root = widget.textSpan;
    if (root == null) continue;
    _walk(root, (span) {
      final style = span.style;
      if (style != null && matches(style)) {
        final text = span.toPlainText(includePlaceholders: false);
        if (text.isNotEmpty) runs.add(text);
      }
    });
  }
  return runs;
}

List<String> _codeRuns(WidgetTester tester, Finder finder) =>
    _styledRuns(tester, finder, (style) => style.fontFamily == 'monospace');

/// The text of a code block, whose key sits on the wrapping container.
String _codeBlock(WidgetTester tester) {
  final text = tester.widget<SelectableText>(
    find.descendant(
      of: find.byKey(const Key('robot-doc-code')),
      matching: find.byType(SelectableText),
    ),
  );
  return text.data ?? text.textSpan?.toPlainText() ?? '';
}

void main() {
  group('Robot Framework markup', () {
    testWidgets('renders every block kind libdoc supports', (tester) async {
      const documentation = '''
Summary with *bold*, _italic_, and \${variable}.

= Examples =
| =Keyword= | =Argument= |
| Log       | hello      |

- First detail
- Second detail

---

Final paragraph
continues on another line.
''';

      await _pump(tester, documentation);

      expect(find.byKey(const Key('robot-doc-heading')), findsOneWidget);
      expect(find.byKey(const Key('robot-doc-table')), findsOneWidget);
      expect(find.byKey(const Key('robot-doc-bullet')), findsNWidgets(2));
      expect(find.byKey(const Key('robot-doc-rule')), findsOneWidget);

      final rendered = _rendered(tester);
      for (final expected in [
        'Summary with bold, italic, and \${variable}.',
        'Examples',
        'Keyword',
        'Argument',
        'hello',
        'First detail',
        'Second detail',
        // libdoc joins paragraph lines and lets them wrap.
        'Final paragraph continues on another line.',
      ]) {
        expect(rendered, contains(expected));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('double-backtick code does not swallow surrounding prose', (
      tester,
    ) async {
      // Reproduces the ExcelSage "Add Sheet" doc: each `` ``code`` `` pair must
      // render on its own, not as one run reaching the next backtick.
      const documentation =
          'The ``Add Sheet`` keyword adds a new sheet, raising a '
          '``WorkbookNotOpenError`` if it is not open.';

      await _pump(tester, documentation);

      final code = _codeRuns(tester, find.byType(SelectableText));
      expect(code, contains('Add Sheet'));
      expect(code, contains('WorkbookNotOpenError'));
      expect(
        code.any((run) => run.contains('keyword adds')),
        isFalse,
        reason: 'prose between code spans must not be highlighted',
      );
      expect(_rendered(tester), contains('keyword adds a new sheet'));
    });

    testWidgets('preformatted blocks drop the leading pipe marker', (
      tester,
    ) async {
      // A '| ' prefix marks preformatted text; libdoc strips it. Without a
      // closing pipe these lines are NOT a table. Authors often pad section
      // headers (***** … *****) to escape bold markup — we show *** … ***.
      const documentation = '''
*Examples*
| ***** Settings *****
| Library    ExcelSage
|
| ***** Variables ******
| @{data}    a    b
|
| ***** Test Cases *****
| Example
|   Open Workbook    file.xlsx
''';

      await _pump(tester, documentation);

      expect(find.byKey(const Key('robot-doc-table')), findsNothing);
      final code = _codeBlock(tester);
      expect(code, contains('*** Settings ***'));
      expect(code, isNot(contains('***** Settings')));
      expect(code, contains('*** Variables ***'));
      expect(code, isNot(contains('******')));
      expect(code, contains('Library    ExcelSage'));
      expect(code, isNot(contains('|')));
      // The blank '|' line survives as a blank line inside the block.
      expect(code, contains('\n\n*** Test Cases ***'));
    });

    testWidgets('example code blocks use editor Robot syntax colors', (
      tester,
    ) async {
      const documentation = '''
*Examples*
| *** Settings ***
| Library    ExcelSage
| *** Test Cases ***
| Example
|    Open Workbook    \${path}
''';
      await _pump(tester, documentation);

      final codeFinder = find.descendant(
        of: find.byKey(const Key('robot-doc-code')),
        matching: find.byType(SelectableText),
      );
      final text = tester.widget<SelectableText>(codeFinder);
      expect(text.textSpan, isNotNull);
      final plain = text.textSpan!.toPlainText();
      expect(plain, contains('*** Settings ***'));
      expect(plain, contains('Library'));
      // Section / keyword tokens should not all share one flat color.
      final colors = <Color>{};
      void collect(InlineSpan span) {
        if (span is TextSpan) {
          final color = span.style?.color;
          if (color != null) colors.add(color);
          for (final child in span.children ?? const <InlineSpan>[]) {
            collect(child);
          }
        }
      }

      collect(text.textSpan!);
      expect(colors.length, greaterThan(1));
    });

    test('padded section headers normalize to three asterisks', () {
      expect(
        normalizeRobotExampleLine('***** Settings *****'),
        '*** Settings ***',
      );
      expect(
        normalizeRobotExampleLine('***** Variables ******'),
        '*** Variables ***',
      );
      expect(
        normalizeRobotExampleLine('  *** Keywords ***'),
        '  *** Keywords ***',
      );
      expect(
        normalizeRobotExampleLine('Library    ExcelSage'),
        'Library    ExcelSage',
      );
    });

    testWidgets('a single backtick is a keyword link, not code', (
      tester,
    ) async {
      // In Robot markup `Name` links to a keyword; only ``x`` is code.
      await _pump(tester, 'See `Open Workbook` and ``literal``.');

      final paragraph = find.byKey(const Key('robot-doc-paragraph'));
      expect(_codeRuns(tester, paragraph), ['literal']);
      final accent = buildAppTheme().extension<AppPalette>()!.accent;
      expect(
        _styledRuns(tester, paragraph, (style) => style.color == accent),
        contains('Open Workbook'),
      );
    });

    testWidgets('emphasis respects libdoc word boundaries', (tester) async {
      // '2 * 3 * 4' has spaces around the stars, so nothing turns bold.
      await _pump(tester, 'Multiply 2 * 3 * 4 and keep *this* bold.');

      final bold = _styledRuns(
        tester,
        find.byKey(const Key('robot-doc-paragraph')),
        (style) => style.fontWeight == FontWeight.w700,
      );
      expect(bold, ['this']);
      expect(_rendered(tester), contains('Multiply 2 * 3 * 4'));
    });
  });

  group('Markdown', () {
    testWidgets('renders headings, fences, lists, quotes and tables', (
      tester,
    ) async {
      const documentation = '''
# Add Sheet

Adds a **new sheet** with `sheet_name`, see [docs](https://example.com).

## Examples

```robotframework
*** Test Cases ***
Example
    Add Sheet    name=Sheet1
```

- First detail
- Second detail

1. Step one
2. Step two

> Raises SheetAlreadyExistsError.

| Argument | Default |
| --- | --- |
| sheet_name | None |
''';

      await _pump(tester, documentation);

      expect(find.byKey(const Key('robot-doc-heading')), findsNWidgets(2));
      expect(find.byKey(const Key('robot-doc-code')), findsOneWidget);
      expect(find.byKey(const Key('robot-doc-bullet')), findsNWidgets(2));
      expect(find.byKey(const Key('robot-doc-ordered')), findsNWidgets(2));
      expect(find.byKey(const Key('robot-doc-quote')), findsOneWidget);
      expect(find.byKey(const Key('robot-doc-table')), findsOneWidget);

      final code = _codeBlock(tester);
      expect(code, contains('*** Test Cases ***'));
      expect(code, isNot(contains('```')));

      final rendered = _rendered(tester);
      for (final expected in [
        'Add Sheet',
        'Adds a new sheet with sheet_name, see docs.',
        'First detail',
        'Step one',
        'Raises SheetAlreadyExistsError.',
        'sheet_name',
        'None',
      ]) {
        expect(rendered, contains(expected));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('** is bold and * is italic, unlike Robot markup', (
      tester,
    ) async {
      await _pump(
        tester,
        'A **strong** and *soft* and ~~gone~~ word.',
        format: RobotDocFormat.markdown,
      );

      final paragraph = find.byKey(const Key('robot-doc-paragraph'));
      expect(
        _styledRuns(tester, paragraph, (s) => s.fontWeight == FontWeight.w700),
        ['strong'],
      );
      expect(
        _styledRuns(tester, paragraph, (s) => s.fontStyle == FontStyle.italic),
        ['soft'],
      );
      expect(
        _styledRuns(
          tester,
          paragraph,
          (s) => s.decoration == TextDecoration.lineThrough,
        ),
        ['gone'],
      );
    });

    testWidgets('a two-digit list marker does not wrap its gutter', (
      tester,
    ) async {
      await _pump(
        tester,
        List.generate(10, (i) => '${i + 1}. Step ${i + 1}').join('\n'),
        format: RobotDocFormat.markdown,
      );

      final rows = find.byKey(const Key('robot-doc-ordered'));
      expect(rows, findsNWidgets(10));
      // '10.' is wider than a single digit; every row must stay one line tall.
      final heights = List.generate(
        10,
        (i) => tester.getRect(rows.at(i)).height,
      );
      expect(heights.toSet(), hasLength(1), reason: 'heights: $heights');
    });

    testWidgets('single backticks are code in Markdown', (tester) async {
      await _pump(
        tester,
        'Pass `sheet_name` to the keyword.',
        format: RobotDocFormat.markdown,
      );

      expect(_codeRuns(tester, find.byType(SelectableText)), ['sheet_name']);
    });
  });

  group('format resolution', () {
    test('maps libdoc doc_format onto a dialect', () {
      expect(RobotDocFormat.fromLibdoc('MARKDOWN'), RobotDocFormat.markdown);
      expect(RobotDocFormat.fromLibdoc('markdown'), RobotDocFormat.markdown);
      expect(RobotDocFormat.fromLibdoc('HTML'), RobotDocFormat.html);
      expect(RobotDocFormat.fromLibdoc('TEXT'), RobotDocFormat.text);
      expect(RobotDocFormat.fromLibdoc('REST'), RobotDocFormat.text);
      // ROBOT is libdoc's default, so it must stay sniffable.
      expect(RobotDocFormat.fromLibdoc('ROBOT'), RobotDocFormat.auto);
      expect(RobotDocFormat.fromLibdoc(null), RobotDocFormat.auto);
      expect(RobotDocFormat.fromLibdoc(''), RobotDocFormat.auto);
    });

    test('sniffs Robot docstrings as Robot', () {
      const excelSage = '''
The ``Add Sheet`` keyword adds a new sheet to the active workbook.

*Examples*
| ***** Settings *****
| Library    ExcelSage
''';
      expect(looksLikeMarkdown(excelSage), isFalse);
      expect(looksLikeMarkdown('= Heading =\n\nSome prose.'), isFalse);
      expect(looksLikeMarkdown('Plain sentence with no markup.'), isFalse);
    });

    test('sniffs Markdown docstrings as Markdown', () {
      expect(looksLikeMarkdown('# Title\n\nBody text.'), isTrue);
      expect(looksLikeMarkdown('Adds a **new sheet** to the book.'), isTrue);
      expect(looksLikeMarkdown('See [docs](https://example.com).'), isTrue);
      expect(looksLikeMarkdown('Example:\n\n```\nAdd Sheet\n```'), isTrue);
      expect(looksLikeMarkdown('| a | b |\n| --- | --- |\n| 1 | 2 |'), isTrue);
    });

    test('an explicit dialect is never overridden by sniffing', () {
      // Markdown-looking text stays Robot when the library declares Robot only
      // through libdoc's default, but an explicit choice always wins.
      const markdownish = '# Title\n\n**bold**';
      expect(
        resolveDocFormat(RobotDocFormat.robot, markdownish),
        RobotDocFormat.robot,
      );
      expect(
        resolveDocFormat(RobotDocFormat.auto, markdownish),
        RobotDocFormat.markdown,
      );
      expect(
        resolveDocFormat(RobotDocFormat.text, markdownish),
        RobotDocFormat.text,
      );
    });

    test('a bare pipe line is not a Markdown table delimiter', () {
      // Robot preformatted blocks contain '|' on its own line.
      expect(isMarkdownTableDelimiter('|'), isFalse);
      expect(isMarkdownTableDelimiter('| Library    ExcelSage'), isFalse);
      expect(isMarkdownTableDelimiter('| --- | --- |'), isTrue);
      expect(isMarkdownTableDelimiter('|:---|---:|'), isTrue);
    });

    testWidgets('TEXT format is shown verbatim', (tester) async {
      const documentation = 'Not *markup*.\n  Indented line stays.';
      await _pump(tester, documentation, format: RobotDocFormat.text);

      expect(find.byKey(const Key('robot-doc-code')), findsOneWidget);
      expect(_codeBlock(tester), documentation);
    });

    test('HTML is normalised into Robot markup', () {
      const html =
          '<p>Adds a <b>new sheet</b> using <code>sheet_name</code>.</p>'
          '<h2>Examples</h2><ul><li>First</li><li>Second</li></ul>'
          '<p>5 &lt; 6 &amp;&amp; ok</p>';
      final robot = htmlToRobotMarkup(html);

      expect(robot, contains('*new sheet*'));
      expect(robot, contains('``sheet_name``'));
      expect(robot, contains('= Examples ='));
      expect(robot, contains('- First'));
      expect(robot, contains('- Second'));
      expect(robot, contains('5 < 6 && ok'));
      // Entities are decoded, but no tags may survive.
      expect(RegExp(r'</?[a-zA-Z][^>]*>').hasMatch(robot), isFalse);
    });

    testWidgets('HTML docs render as rich text, not tag soup', (tester) async {
      await _pump(
        tester,
        '<p>Adds a <b>new sheet</b>.</p><h2>Examples</h2>',
        format: RobotDocFormat.html,
      );

      final rendered = _rendered(tester);
      expect(rendered, contains('Adds a new sheet.'));
      expect(rendered, contains('Examples'));
      expect(rendered, isNot(contains('<b>')));
      expect(find.byKey(const Key('robot-doc-heading')), findsOneWidget);
    });
  });

  testWidgets('shows a quiet empty state when libdoc has no text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: RobotDocumentation(documentation: '')),
      ),
    );

    expect(find.text('No documentation available.'), findsOneWidget);
  });
}
