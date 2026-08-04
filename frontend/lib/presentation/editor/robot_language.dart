import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';

/// Lightweight Robot Framework highlight.js Mode for re_editor / re_highlight.
///
/// Token categories (DSL vs library):
/// - section: `*** Settings ***` (language)
/// - keyword / meta: suite settings, local `[…]` settings, control-flow DSL
/// - built_in: library keyword *calls* (Log, Create Dictionary, user libs)
/// - variable: `${}` `@{}` `&{}` `%{}`
/// - title: test / user-keyword names
/// - comment / string / number / attr / continuation
///
/// Documentation lines are consumed as strings so words like `for` / `if`
/// inside `[Documentation]` are not painted as control-flow keywords.
final Mode langRobot = Mode(
  name: 'robot',
  aliases: ['robotframework', 'robot'],
  caseInsensitive: true,
  contains: <Mode>[
    Mode(className: 'comment', begin: '#', end: r'$'),

    // Continuation `...`
    Mode(
      className: 'meta',
      begin: r'^\s*\.\.\.',
      relevance: 5,
    ),

    // *** Settings *** / legacy singular / Comments
    Mode(
      className: 'section',
      begin: r'^\*{3}\s*('
          r'Settings?|Variables?|Test Cases?|Tasks?|Keywords?|Comments?'
          r')\s*\*{3}',
      end: r'$',
      relevance: 10,
    ),

    // ${x} @{x} &{x} %{x} — match early so keyword rules never swallow
    // assignment cells like `${source}    Create Dictionary`.
    Mode(
      className: 'variable',
      begin: r'[\$@&%]\{[^{}\n]+\}',
      relevance: 10,
    ),

    // Local [Documentation] … rest of line — exclusive mode so IF/FOR/IN
    // inside doc text are not painted as control-flow keywords.
    Mode(
      className: 'string',
      begin: r'\[Documentation\]',
      end: r'$',
      returnBegin: true,
      contains: <Mode>[
        Mode(
          className: 'meta',
          begin: r'\[Documentation\]',
          relevance: 10,
        ),
        Mode(
          className: 'variable',
          begin: r'[\$@&%]\{[^{}\n]+\}',
        ),
      ],
      relevance: 10,
    ),

    // Suite-level Documentation setting — same idea.
    Mode(
      className: 'string',
      begin: r'^Documentation\b',
      end: r'$',
      returnBegin: true,
      contains: <Mode>[
        Mode(
          className: 'keyword',
          begin: r'^Documentation\b',
          relevance: 10,
        ),
        Mode(
          className: 'variable',
          begin: r'[\$@&%]\{[^{}\n]+\}',
        ),
      ],
      relevance: 10,
    ),

    // Other local settings: [Tags] / [Setup] / …
    Mode(
      className: 'meta',
      begin:
          r'\[(Tags|Setup|Teardown|Timeout|Arguments|Template|Return)\]',
    ),

    // Suite / import settings at column 0 (Documentation handled above)
    Mode(
      className: 'keyword',
      begin:
          r'^(Library|Resource|Variables|Metadata|Name|'
          r'Suite Setup|Suite Teardown|Test Setup|Test Teardown|'
          r'Test Timeout|Test Template|Test Tags|Force Tags|Default Tags|'
          r'Keyword Tags|Task Setup|Task Teardown|Task Template|Task Timeout)\b',
    ),

    // Control-flow DSL (NOT BuiltIn library keywords) — after Documentation
    // so doc text does not pick these up.
    Mode(
      className: 'keyword',
      begin: r'\b('
          r'IF|ELSE IF|ELSE|END|FOR|WHILE|BREAK|CONTINUE|RETURN|'
          r'TRY|EXCEPT|FINALLY|GROUP|VAR|'
          r'IN RANGE|IN ENUMERATE|IN ZIP|IN|'
          r'WITH NAME|AS|AND'
          r')\b',
      relevance: 8,
    ),

    // Named arguments: user=
    Mode(
      className: 'attr',
      begin: r'\b[A-Za-z_][\w]*=',
      relevance: 0,
    ),

    // Indented library / user keyword *calls* (BuiltIn + others)
    Mode(
      className: 'built_in',
      begin:
          r'^\s{2,}(?!\[|#|[\$@&%])'
          r'(?!IF\b|ELSE IF\b|ELSE\b|END\b|FOR\b|WHILE\b|BREAK\b|CONTINUE\b|'
          r'RETURN\b|TRY\b|EXCEPT\b|FINALLY\b|GROUP\b|VAR\b|'
          r'IN RANGE\b|IN ENUMERATE\b|IN ZIP\b|IN\b|WITH NAME\b|AS\b|AND\b)'
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
          r'(?!IF\b|ELSE IF\b|ELSE\b|END\b|FOR\b|WHILE\b|BREAK\b|CONTINUE\b|'
          r'RETURN\b|TRY\b|EXCEPT\b|FINALLY\b|GROUP\b|VAR\b)'
          r'[A-Za-z_][\w]*(?: [A-Za-z_][\w]*)*'
          r'(?=\s{2,}|\t|$)',
      relevance: 0,
    ),

    // Test case / user-keyword *names* at column 0
    Mode(
      className: 'title',
      begin:
          r'^(?!\*|\#|\[)'
          r'(?!Library\b|Resource\b|Variables\b|Documentation\b|Metadata\b|Name\b|'
          r'Suite Setup\b|Suite Teardown\b|Test Setup\b|Test Teardown\b|'
          r'Test Timeout\b|Test Template\b|Force Tags\b|Default Tags\b|'
          r'Test Tags\b|Keyword Tags\b|'
          r'Task Setup\b|Task Teardown\b|Task Template\b|Task Timeout\b)'
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
/// Magenta = DSL (sections handled separately; settings + control flow).
/// Teal = library keyword calls (BuiltIn + user libraries).
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
  // Suite settings / control-flow DSL — magenta
  'keyword': const TextStyle(
    color: Color(0xFFC586C0),
    fontWeight: FontWeight.w700,
  ),
  // Local [Documentation] / continuation — magenta
  'meta': const TextStyle(
    color: Color(0xFFC586C0),
    fontWeight: FontWeight.w700,
  ),
  // Log / Create Dictionary / user library calls — teal
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
