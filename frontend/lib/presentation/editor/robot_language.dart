import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../core/theme/app_theme.dart';

/// Lightweight Robot Framework highlight.js Mode for re_editor / re_highlight.
final Mode langRobot = Mode(
  name: 'robot',
  aliases: ['robotframework', 'robot'],
  caseInsensitive: true,
  contains: <Mode>[
    Mode(className: 'comment', begin: '#', end: r'$'),
    Mode(
      className: 'section',
      begin: r'^\*+\s*(Settings|Variables|Test Cases|Tasks|Keywords)\s*\**',
      end: r'$',
      relevance: 10,
    ),
    Mode(
      className: 'keyword',
      begin:
          r'^\s*\[(Documentation|Tags|Setup|Teardown|Timeout|Arguments|Template)\]',
      end: r'$',
    ),
    Mode(
      className: 'keyword',
      begin:
          r'\b(Library|Resource|Variables|Documentation|Metadata|IF|ELSE IF|ELSE|END|'
          r'FOR|WHILE|BREAK|CONTINUE|RETURN|TRY|EXCEPT|FINALLY|'
          r'Log|Log To Console|Set Variable|Should Be Equal|Should Contain|Create List|'
          r'Run Keyword|Run Keywords|Wait Until Keyword Succeeds|Sleep|Fail|Pass Execution)\b',
    ),
    Mode(
      className: 'variable',
      begin: r'(\$\{[^}]+\}|@\{[^}]+\}|&\{[^}]+\}|%\{[^}]+\})',
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
  ],
);

/// Syntax colors mapped onto the Robot Studio palette.
final Map<String, TextStyle> robotStudioHighlightTheme = {
  'comment': const TextStyle(color: AppColors.textMuted, fontStyle: FontStyle.italic),
  'section': const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
  'keyword': const TextStyle(color: AppColors.info, fontWeight: FontWeight.w600),
  'built_in': const TextStyle(color: AppColors.info),
  'variable': const TextStyle(color: AppColors.warning),
  'string': const TextStyle(color: AppColors.success),
  'title': const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
  'number': const TextStyle(color: AppColors.warning),
  'meta': const TextStyle(color: AppColors.accentMuted),
  'params': const TextStyle(color: AppColors.textSecondary),
  'attr': const TextStyle(color: AppColors.accent),
  'root': const TextStyle(color: AppColors.textPrimary),
};
