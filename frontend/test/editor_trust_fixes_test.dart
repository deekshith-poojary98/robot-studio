import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/presentation/editor/editor_language_widgets.dart';
import 'package:robot_studio/presentation/editor/robot_language.dart';

void main() {
  group('section completion prefix', () {
    test('includes *** so Tab replaces the whole header fragment', () {
      const line = '*** Key';
      expect(
        RobotAutocompletePromptsBuilder.prefixAt(line, line.length),
        '*** Key',
      );
    });

    test('includes [ for local settings', () {
      const line = '    [Doc';
      expect(
        RobotAutocompletePromptsBuilder.prefixAt(line, line.length),
        '[Doc',
      );
    });

    test('keeps normal keyword prefixes', () {
      const line = '    Log To';
      expect(
        RobotAutocompletePromptsBuilder.prefixAt(line, line.length),
        'Log To',
      );
    });

    test('argument prefix is the current cell, not the previous value', () {
      const line =
          '    Evaluate    expression=random.randint(1,10)    modules=random    name';
      expect(
        RobotAutocompletePromptsBuilder.prefixAt(line, line.length),
        'name',
      );
    });

    test('Keywords header replaces *** Key without doubling stars', () {
      const prefix = '*** Key';
      const insert = '*** Keywords ***';
      expect(
        RobotAutocompletePromptsBuilder.prefixAt(prefix, prefix.length),
        prefix,
      );
      expect(prefix.replaceFirst(prefix, insert), insert);
    });
  });

  testWidgets('autocomplete popup shows label, inserts multi-line snippet', (
    tester,
  ) async {
    final builder = RobotAutocompletePromptsBuilder([
      const CompletionItemInfo(
        label: 'FOR … IN RANGE',
        kind: 'dsl',
        detail: 'RF DSL',
        documentation: '',
        insertText: 'FOR    \${i}    IN RANGE    10\n    Log    \${i}\nEND',
      ),
    ]);

    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine('    F'),
              const CodeLineSelection.collapsed(index: 0, offset: 5),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(value, isNotNull);
    expect(value!.prompts, hasLength(1));
    expect(value!.prompts.first.word, 'FOR … IN RANGE');
    expect(value!.prompts.first.word.contains('\n'), isFalse);
    expect(
      value!.prompts.first.autocomplete.word,
      'FOR    \${i}    IN RANGE    10\n'
      '        Log    \${i}\n'
      '    END',
    );
  });

  testWidgets('next-arg name= shows even when keyword completions are stale', (
    tester,
  ) async {
    const signature = SignatureHelpInfo(
      keyword: 'Evaluate',
      activeParameter: 1,
      parameters: [
        SignatureParameterInfo(
          label: 'expression',
          name: 'expression',
          required: true,
        ),
        SignatureParameterInfo(label: 'modules', name: 'modules'),
        SignatureParameterInfo(label: 'namespace', name: 'namespace'),
      ],
    );
    const line = '    Evaluate    int(1, 10)    ';
    final builder = RobotAutocompletePromptsBuilder([
      for (var i = 0; i < 25; i++)
        CompletionItemInfo(label: 'Keyword$i', kind: 'keyword'),
    ], signature: signature);

    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine(line),
              CodeLineSelection.collapsed(index: 0, offset: line.length),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(value, isNotNull);
    expect(value!.prompts.map((p) => p.word), ['modules=', 'namespace=']);
  });

  testWidgets('typing name after a filled arg offers namespace=', (
    tester,
  ) async {
    const signature = SignatureHelpInfo(
      keyword: 'Evaluate',
      activeParameter: 2,
      parameters: [
        SignatureParameterInfo(label: 'expression', name: 'expression'),
        SignatureParameterInfo(label: 'modules', name: 'modules'),
        SignatureParameterInfo(label: 'namespace', name: 'namespace'),
      ],
    );
    const line =
        '    Evaluate    expression=random.randint(1,10)    modules=random    name';
    final builder = RobotAutocompletePromptsBuilder(
      const [],
      signature: signature,
    );

    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine(line),
              CodeLineSelection.collapsed(index: 0, offset: line.length),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(value, isNotNull);
    expect(value!.input, 'name');
    expect(value!.prompts.map((p) => p.word), ['namespace=']);
  });

  testWidgets('named-arg popup stays closed inside an expression value', (
    tester,
  ) async {
    const signature = SignatureHelpInfo(
      keyword: 'Evaluate',
      activeParameter: 1,
      parameters: [
        SignatureParameterInfo(label: 'expression', name: 'expression'),
        SignatureParameterInfo(label: 'modules', name: 'modules'),
        SignatureParameterInfo(label: 'namespace', name: 'namespace'),
      ],
    );
    const line = r'    ${num}=    Evaluate    expression=random.randint(';
    final builder = RobotAutocompletePromptsBuilder(const [
      CompletionItemInfo(label: 'modules=', kind: 'parameter'),
      CompletionItemInfo(label: 'namespace=', kind: 'parameter'),
    ], signature: signature);

    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine(line),
              CodeLineSelection.collapsed(index: 0, offset: line.length),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      RobotAutocompletePromptsBuilder.isTypingNamedArgValue(line, line.length),
      isTrue,
    );
    expect(value, isNull);
  });

  test('namedArgsFromSignature skips filled positional and present names', () {
    const signature = SignatureHelpInfo(
      keyword: 'Evaluate',
      activeParameter: 1,
      parameters: [
        SignatureParameterInfo(label: 'expression', name: 'expression'),
        SignatureParameterInfo(label: 'modules', name: 'modules'),
        SignatureParameterInfo(label: 'namespace', name: 'namespace'),
      ],
    );
    const line = '    Evaluate    int(1, 10)    ';
    final items = RobotAutocompletePromptsBuilder.namedArgsFromSignature(
      line,
      line.length,
      signature,
    );
    expect(items.map((i) => i.label), ['modules=', 'namespace=']);
    expect(
      RobotAutocompletePromptsBuilder.isArgumentSlot(
        line,
        line.length,
        signature,
      ),
      isTrue,
    );
    expect(
      RobotAutocompletePromptsBuilder.isTypingNamedArgValue(
        '    Evaluate    modules=',
        '    Evaluate    modules='.length,
      ),
      isTrue,
    );
    expect(
      RobotAutocompletePromptsBuilder.isTypingNamedArgValue(
        '    Evaluate    modules',
        '    Evaluate    modules'.length,
      ),
      isFalse,
    );
    expect(
      RobotAutocompletePromptsBuilder.isTypingNamedArgValue(
        '    Evaluate    int(1, 10)',
        '    Evaluate    int(1, 10)'.length,
      ),
      isTrue,
    );
  });

  test('indentMultilineInsert nests body under current line indent', () {
    expect(
      RobotAutocompletePromptsBuilder.indentMultilineInsert(
        'FOR    \${i}    IN RANGE    10\n    Log    \${i}\nEND',
        '    ',
      ),
      'FOR    \${i}    IN RANGE    10\n        Log    \${i}\n    END',
    );
    expect(
      RobotAutocompletePromptsBuilder.indentMultilineInsert('Log', '    '),
      'Log',
    );
    expect(RobotAutocompletePromptsBuilder.leadingIndentOf('    F'), '    ');
  });

  group('Documentation highlighting', () {
    late Highlight highlight;

    setUp(() {
      highlight = Highlight();
      highlight.registerLanguage('robot', langRobot);
    });

    test('does not classify IF/FOR inside [Documentation] as keywords', () {
      final html = highlight
          .highlight(
            code: '    [Documentation]    Login for if while users\n',
            language: 'robot',
          )
          .toHtml();
      // Control words should be plain string scope, not hljs-keyword.
      expect(html.contains('hljs-keyword">if'), isFalse);
      expect(html.contains('hljs-keyword">for'), isFalse);
      expect(html.contains('hljs-keyword">while'), isFalse);
      expect(html.contains('hljs-meta'), isTrue);
    });

    test('still highlights IF in executable lines', () {
      final html = highlight
          .highlight(code: '    IF    \${ok}\n', language: 'robot')
          .toHtml();
      expect(html.toLowerCase(), contains('hljs-keyword'));
      expect(html.toLowerCase(), contains('>if<'));
    });

    test('does not paint DSL words inside argument values', () {
      final html = highlight
          .highlight(
            code:
                '    Sleep    time_=5s    reason=as for if in as var with me ok\n',
            language: 'robot',
          )
          .toHtml();
      expect(html.toLowerCase().contains('hljs-keyword">as'), isFalse);
      expect(html.toLowerCase().contains('hljs-keyword">for'), isFalse);
      expect(html.toLowerCase().contains('hljs-keyword">if'), isFalse);
      expect(html.toLowerCase().contains('hljs-keyword">in'), isFalse);
      expect(html.toLowerCase().contains('hljs-keyword">var'), isFalse);
      expect(html.toLowerCase(), contains('hljs-attr'));
    });

    test('still highlights FOR / IN RANGE / AS as their own cells', () {
      final html = highlight
          .highlight(
            code:
                '    FOR    \${i}    IN RANGE    10\n'
                '    EXCEPT    boom    AS    \${err}\n',
            language: 'robot',
          )
          .toHtml();
      final lower = html.toLowerCase();
      expect(lower, contains('hljs-keyword'));
      expect(lower, contains('>for<'));
      expect(lower, contains('>in range<'));
      expect(lower, contains('>as<'));
    });
  });

  group('Keyword name highlighting', () {
    late Highlight highlight;

    setUp(() {
      highlight = Highlight();
      highlight.registerLanguage('robot', langRobot);
    });

    String render(String code) =>
        highlight.highlight(code: code, language: 'robot').toHtml();

    const suite =
        '*** Keywords ***\n'
        'Click\n'
        '    Click Element    locator=x\n'
        '%SEPARATOR%\n'
        'Type\n'
        '    [Documentation]    doc\n';

    test('column-0 name stays a title after a whitespace-only line', () {
      // A blank line with indentation must not extend the previous keyword
      // call across the newline and repaint `Type` as a library call.
      for (final separator in ['', '    ', '\t', '  \t ']) {
        final html = render(suite.replaceFirst('%SEPARATOR%', separator));
        expect(
          html,
          contains('<span class="hljs-title">Type</span>'),
          reason: 'separator ${separator.codeUnits}',
        );
        expect(
          html.contains('hljs-built_in">$separator\nType'),
          isFalse,
          reason: 'separator ${separator.codeUnits}',
        );
      }
    });

    test('indented calls are still built_in', () {
      final html = render(suite.replaceFirst('%SEPARATOR%', '    '));
      expect(html, contains('hljs-built_in">    Click Element'));
      expect(html, contains('<span class="hljs-title">Click</span>'));
    });
  });
}
