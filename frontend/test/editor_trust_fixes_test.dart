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

    test('python attribute uses suffix after dot', () {
      const line = 'json.d';
      expect(RobotAutocompletePromptsBuilder.prefixAt(line, line.length), 'd');
    });

    test('python attribute after dot uses empty prefix', () {
      const line = 'json.';
      expect(RobotAutocompletePromptsBuilder.prefixAt(line, line.length), '');
      expect(
        RobotAutocompletePromptsBuilder.isPythonAttributeContext(
          line,
          line.length,
        ),
        isTrue,
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

  testWidgets('python json.d shows Jedi-style member completions', (
    tester,
  ) async {
    final builder = RobotAutocompletePromptsBuilder([
      const CompletionItemInfo(
        label: 'FOR … IN RANGE',
        kind: 'dsl',
        provider: 'dsl',
      ),
      const CompletionItemInfo(
        label: 'dump',
        kind: 'function',
        provider: 'python_jedi',
      ),
      const CompletionItemInfo(
        label: 'dumps',
        kind: 'function',
        provider: 'python_jedi',
      ),
      const CompletionItemInfo(
        label: 'loads',
        kind: 'function',
        provider: 'python_jedi',
      ),
    ], filePath: '/proj/test.py');

    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine('json.d'),
              const CodeLineSelection.collapsed(index: 0, offset: 6),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(value, isNotNull);
    expect(value!.input, 'd');
    expect(value!.prompts.map((p) => p.word), contains('dumps'));
    expect(
      value!.prompts.map((p) => p.word),
      isNot(contains('FOR … IN RANGE')),
    );
  });

  testWidgets('python assignment keeps local names (no robot cell rules)', (
    tester,
  ) async {
    final builder = RobotAutocompletePromptsBuilder(const [
      CompletionItemInfo(
        label: 'name',
        kind: 'parameter',
        provider: 'python_jedi',
        insertText: 'name',
      ),
      CompletionItemInfo(
        label: 'NameError',
        kind: 'class',
        provider: 'python_jedi',
        insertText: 'NameError',
      ),
    ], filePath: '/proj/bank.py');

    const line = '        self.name = name';
    late CodeAutocompleteEditingValue? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = builder.build(
              context,
              const CodeLine(line),
              const CodeLineSelection.collapsed(index: 0, offset: line.length),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(value, isNotNull);
    expect(value!.input, 'name');
    // ``self.name = na|`` is an assignment, not a Robot ``name=`` cell: the
    // local parameter must stay, and rank above the builtin exception.
    expect(value!.prompts.map((p) => p.word).toList(), ['name', 'NameError']);
  });

  test('kind label distinguishes same-prefix rows', () {
    expect(kindLabel('parameter'), 'param');
    expect(kindLabel('class'), 'class');
    expect(kindLabel('function'), 'def');
    expect(kindLabel('dsl'), '');
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

  test('namedArgsFromSignature skips / and * signature markers', () {
    const signature = SignatureHelpInfo(
      keyword: 'Run Keyword If',
      activeParameter: 1,
      parameters: [
        SignatureParameterInfo(
          label: 'condition',
          name: 'condition',
          kind: 'positional_only',
        ),
        SignatureParameterInfo(
          label: 'name',
          name: 'name',
          kind: 'positional_only',
        ),
        SignatureParameterInfo(
          label: '/',
          name: '/',
          kind: 'positional_only_marker',
        ),
        SignatureParameterInfo(
          label: '*args',
          name: 'args',
          kind: 'var_positional',
        ),
      ],
    );
    const line = '    Run Keyword If    \${press}    ';
    final items = RobotAutocompletePromptsBuilder.namedArgsFromSignature(
      line,
      line.length,
      signature,
    );
    expect(items.map((i) => i.label), ['name=']);
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

    test('keyword after single assignment is built_in', () {
      final html = render('    \${data}=    Fetch Sheet Data    Sheet1\n');
      expect(html, contains('hljs-built_in'));
      expect(html.toLowerCase(), contains('fetch sheet data'));
    });

    test('keyword after multi-assignment is built_in', () {
      final html = render('    \${posts}    \${response}=    Get All Posts\n');
      expect(
        html.toLowerCase(),
        contains('hljs-built_in">get all posts'),
        reason: html,
      );
      // Assignments stay variables, not swallowed into the keyword span.
      expect(html, contains('hljs-variable'));
      expect(html, contains('\${posts}'));
    });

    test('embedded args in a keyword definition stay variables', () {
      final html = render(
        'Login to the application with \${e_type} email and \${p_type} password\n',
      );
      expect(html, contains('hljs-title'), reason: html);
      expect(html, contains('hljs-variable">\${e_type}</span>'), reason: html);
      expect(html, contains('hljs-variable">\${p_type}</span>'), reason: html);
    });

    test('embedded-argument keyword call is built_in', () {
      final html = render(
        '    Fill \${e_type} email and \${p_type} password\n',
      );
      expect(html, contains('hljs-built_in'), reason: html);
      expect(html.toLowerCase(), contains('fill'), reason: html);
      expect(html, contains('hljs-variable">\${e_type}</span>'), reason: html);
      expect(html, contains('hljs-variable">\${p_type}</span>'), reason: html);
    });

    test('embedded-argument keyword after assignment is built_in', () {
      final html = render(
        '    \${status}    Fill \${e_type} email and \${p_type} password\n',
      );
      expect(html, contains('hljs-built_in'), reason: html);
      expect(html.toLowerCase(), contains('fill'), reason: html);
      expect(html, contains('hljs-variable">\${status}</span>'), reason: html);
      expect(html, contains('hljs-variable">\${e_type}</span>'), reason: html);
      expect(html, contains('hljs-variable">\${p_type}</span>'), reason: html);
    });

    test('embedded-argument call does not swallow the next cell', () {
      final html = render(
        '    Fill \${e_type} email and \${p_type} password    leftover\n',
      );
      expect(html, contains('hljs-built_in'), reason: html);
      expect(html, contains('hljs-variable">\${e_type}</span>'), reason: html);
      expect(html.contains('leftover'), isTrue, reason: html);
      expect(
        RegExp('hljs-built_in">[^<]*leftover').hasMatch(html),
        isFalse,
        reason: html,
      );
    });
  });
}
