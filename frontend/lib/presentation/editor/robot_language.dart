import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';

/// Lightweight Robot Framework highlight.js Mode for re_editor / re_highlight.
///
/// Aimed at VS Code Dark+ / Robot Framework extension coloring:
/// - sky blue: section headers + ${variables}
/// - teal: keyword *calls* (Create Dictionary, Log, …)
/// - magenta: settings names (Library, Documentation, [Tags], IF/…)
/// - yellow: test/keyword *names* + named-arg keys
/// - white: plain arguments / library names
final Mode langRobot = Mode(
  name: 'robot',
  aliases: ['robotframework', 'robot'],
  caseInsensitive: true,
  contains: <Mode>[
    Mode(className: 'comment', begin: '#', end: r'$'),

    // *** Settings *** / *** Test Cases ***
    Mode(
      className: 'section',
      begin: r'^\*{3}\s*(Settings|Variables|Test Cases|Tasks|Keywords)\s*\*{3}',
      end: r'$',
      relevance: 10,
    ),

    // ${x} @{x} &{x} %{x} — match early + high relevance so keyword rules
    // never swallow assignment cells like `${source}    Create Dictionary`.
    Mode(
      className: 'variable',
      begin: r'[\$@&%]\{[^{}\n]+\}',
      relevance: 10,
    ),

    // [Documentation] / [Tags] / … — bracket token only
    Mode(
      className: 'meta',
      begin:
          r'\[(Documentation|Tags|Setup|Teardown|Timeout|Arguments|Template|Return)\]',
    ),

    // Settings-table names at column 0
    Mode(
      className: 'keyword',
      begin:
          r'^(Library|Resource|Variables|Documentation|Metadata|Suite Setup|'
          r'Suite Teardown|Test Setup|Test Teardown|Test Timeout|Force Tags|'
          r'Default Tags|Test Tags)\b',
    ),

    // Control flow
    Mode(
      className: 'keyword',
      begin:
          r'\b(IF|ELSE IF|ELSE|END|FOR|WHILE|BREAK|CONTINUE|RETURN|TRY|EXCEPT|'
          r'FINALLY)\b',
    ),

    // Named arguments: user=
    Mode(
      className: 'attr',
      begin: r'\b[A-Za-z_][\w]*=',
      relevance: 0,
    ),

    // Indented keyword call (no leading ${assignment} — that is colored above).
    Mode(
      className: 'built_in',
      begin:
          r'^\s{2,}(?!\[|#|[\$@&%])'
          r'[A-Za-z_][\w]*(?: [A-Za-z_][\w]*)*'
          r'(?=\s{2,}|\t|$)',
      relevance: 0,
    ),

    // Keyword call after `${result}    ` on an indented line.
    Mode(
      className: 'built_in',
      begin:
          r'(?<=^\s{2,}[\$@&%]\{[^{}\n]+\}\s{2,})'
          r'(?!\[|#)'
          r'[A-Za-z_][\w]*(?: [A-Za-z_][\w]*)*'
          r'(?=\s{2,}|\t|$)',
      relevance: 0,
    ),

    // Test case / user-keyword *names* at column 0
    Mode(
      className: 'title',
      begin:
          r'^(?!\*|\#|\[)'
          r'(?!Library\b|Resource\b|Variables\b|Documentation\b|Metadata\b|'
          r'Suite Setup\b|Suite Teardown\b|Test Setup\b|Test Teardown\b|'
          r'Test Timeout\b|Force Tags\b|Default Tags\b|Test Tags\b)'
          r'[A-Za-z_].*$',
      relevance: 0,
    ),

    Mode(
      className: 'string',
      begin: r'"',
      end: r'"',
      contains: <Mode>[BACKSLASH_ESCAPE],
    ),
    Mode(
      className: 'string',
      begin: r"'",
      end: r"'",
      contains: <Mode>[BACKSLASH_ESCAPE],
    ),
    Mode(className: 'number', begin: r'\b\d+(\.\d+)?\b'),
  ],
);

/// VS Code Dark+ / Robot Framework extension palette.
final Map<String, TextStyle> robotStudioHighlightTheme = {
  'root': const TextStyle(color: Color(0xFFD4D4D4)),
  'comment': const TextStyle(
    color: Color(0xFF6A9955),
    fontStyle: FontStyle.italic,
  ),
  // *** Settings *** — sky blue
  'section': const TextStyle(
    color: Color(0xFF9CDCFE),
    fontWeight: FontWeight.w700,
  ),
  // Library / Documentation / IF — magenta
  'keyword': const TextStyle(
    color: Color(0xFFC586C0),
    fontWeight: FontWeight.w700,
  ),
  'meta': const TextStyle(
    color: Color(0xFFC586C0),
    fontWeight: FontWeight.w700,
  ),
  // Create Dictionary / Log / … — teal
  'built_in': const TextStyle(
    color: Color(0xFF4EC9B0),
    fontWeight: FontWeight.w700,
  ),
  // Test / keyword names — yellow
  'title': const TextStyle(
    color: Color(0xFFDCDCAA),
    fontWeight: FontWeight.w700,
  ),
  // ${var} — sky blue
  'variable': const TextStyle(color: Color(0xFF9CDCFE)),
  'template-variable': const TextStyle(color: Color(0xFF9CDCFE)),
  // user= — yellow
  'attr': const TextStyle(color: Color(0xFFDCDCAA)),
  'string': const TextStyle(color: Color(0xFFCE9178)),
  'number': const TextStyle(color: Color(0xFFB5CEA8)),
  'params': const TextStyle(color: Color(0xFFD4D4D4)),
};
