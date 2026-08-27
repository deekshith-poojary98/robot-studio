import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../core/theme/app_theme.dart';
import 'robot_language.dart';

/// Extensions that get Python intelligence. Stub (`.pyi`) and script (`.pyw`)
/// files are the same language, so gating them out would give them
/// highlighting but no completions, hover, or diagnostics.
const pythonSuffixes = ['.py', '.pyi', '.pyw'];
const robotSuffixes = ['.robot', '.resource'];

bool isPythonPath(String path) {
  final lower = path.toLowerCase();
  return pythonSuffixes.any(lower.endsWith);
}

bool isRobotPath(String path) {
  final lower = path.toLowerCase();
  return robotSuffixes.any(lower.endsWith);
}

/// A file the language service can analyse (Robot or Python).
bool isSourcePath(String path) => isPythonPath(path) || isRobotPath(path);

/// Maps a file path to a `re_editor` highlight theme for the active [palette].
///
/// - `.robot` / `.resource` → custom [langRobot]
/// - other extensions → matching `re_highlight` builtin grammar when known
/// - unknown types → no highlighting (plain text)
CodeHighlightTheme? codeThemeForPath(String path, AppPalette palette) {
  final resolved = _resolveLanguage(path);
  if (resolved == null) return null;
  return CodeHighlightTheme(
    languages: {resolved.id: CodeHighlightThemeMode(mode: resolved.mode)},
    theme: editorHighlightTheme(palette),
  );
}

({String id, Mode mode})? _resolveLanguage(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1) : '';

  // Custom Robot Framework grammar (not shipped by re_highlight).
  if (ext == 'robot' || ext == 'resource') {
    return (id: 'robot', mode: langRobot);
  }

  final byName = _filenameLanguages[name];
  if (byName != null) {
    final mode = builtinAllLanguages[byName];
    if (mode != null) return (id: byName, mode: mode);
  }

  if (ext.isEmpty) return null;
  final id = _extensionLanguages[ext];
  if (id == null) return null;
  final mode = builtinAllLanguages[id];
  if (mode == null) return null;
  return (id: id, mode: mode);
}

/// Common filenames → re_highlight language id.
const _filenameLanguages = <String, String>{
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'gnumakefile': 'makefile',
  'cmakelists.txt': 'cmake',
  '.bashrc': 'bash',
  '.bash_profile': 'bash',
  '.zshrc': 'bash',
  '.profile': 'bash',
  'nginx.conf': 'nginx',
  'apache.conf': 'apache',
  'httpd.conf': 'apache',
};

/// File extension → re_highlight language id.
const _extensionLanguages = <String, String>{
  // Scripting / general purpose
  'py': 'python',
  'pyw': 'python',
  'pyi': 'python',
  'gyp': 'python',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'dart': 'dart',
  'rb': 'ruby',
  'php': 'php',
  'pl': 'perl',
  'pm': 'perl',
  'lua': 'lua',
  'r': 'r',
  'jl': 'julia',
  'groovy': 'groovy',
  'gradle': 'gradle',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'scala': 'scala',
  'sc': 'scala',
  'swift': 'swift',
  'go': 'go',
  'rs': 'rust',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hrl': 'erlang',
  'hs': 'haskell',
  'lhs': 'haskell',
  'clj': 'clojure',
  'cljs': 'clojure',
  'cljc': 'clojure',
  'edn': 'clojure',
  'lisp': 'lisp',
  'cl': 'lisp',
  'el': 'lisp',
  'scm': 'scheme',
  'rkt': 'scheme',
  'fs': 'fsharp',
  'fsi': 'fsharp',
  'fsx': 'fsharp',
  'ml': 'ocaml',
  'mli': 'ocaml',
  'nim': 'nim',
  'cr': 'crystal',
  'd': 'd',
  'v': 'verilog',
  'sv': 'verilog',
  'vhd': 'vhdl',
  'vhdl': 'vhdl',
  'ada': 'ada',
  'adb': 'ada',
  'ads': 'ada',
  'pas': 'delphi',
  'pp': 'delphi',
  'dpr': 'delphi',
  'vb': 'vbnet',
  'vbs': 'vbscript',
  'ps1': 'powershell',
  'psm1': 'powershell',
  'psd1': 'powershell',
  'bat': 'dos',
  'cmd': 'dos',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'ksh': 'bash',
  'fish': 'bash',
  'awk': 'awk',

  // C family
  'c': 'c',
  'h': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'hh': 'cpp',
  'hxx': 'cpp',
  'cs': 'csharp',
  'm': 'objectivec',
  'mm': 'objectivec',

  // Web / markup
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'xml': 'xml',
  'xsl': 'xml',
  'xsd': 'xml',
  'svg': 'xml',
  'vue': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'styl': 'stylus',
  'md': 'markdown',
  'markdown': 'markdown',
  'mdown': 'markdown',

  // Data / config
  'json': 'json',
  'jsonc': 'json',
  'json5': 'json',
  'ipynb': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'properties': 'properties',
  'env': 'properties',
  'sql': 'sql',
  'graphql': 'graphql',
  'gql': 'graphql',
  'proto': 'protobuf',
  'thrift': 'thrift',

  // Build / devops
  'dockerfile': 'dockerfile',
  'cmake': 'cmake',
  'makefile': 'makefile',
  'mk': 'makefile',
  'nginx': 'nginx',
  'diff': 'diff',
  'patch': 'diff',

  // Misc
  'java': 'java',
  'wasm': 'wasm',
  'wat': 'wasm',
  'vim': 'vim',
  'tex': 'latex',
  'ltx': 'latex',
  'bib': 'latex',
  'asm': 'x86asm',
  's': 'x86asm',
  'f': 'fortran',
  'for': 'fortran',
  'f90': 'fortran',
  'f95': 'fortran',
  'mat': 'matlab',
  'matlab': 'matlab',
  'sas': 'sas',
  'do': 'stata',
  'stata': 'stata',
  'gml': 'gml',
  'feature': 'gherkin',
  'coffee': 'coffeescript',
  'litcoffee': 'coffeescript',
};

/// Full token theme for builtin grammars + Robot Studio palette.
Map<String, TextStyle> editorHighlightTheme(AppPalette palette) => {
  'root': TextStyle(color: palette.textPrimary),
  'comment': TextStyle(color: palette.textMuted, fontStyle: FontStyle.italic),
  'quote': TextStyle(color: palette.textMuted, fontStyle: FontStyle.italic),
  'doctag': TextStyle(color: palette.info, fontWeight: FontWeight.w600),
  'keyword': TextStyle(color: palette.info, fontWeight: FontWeight.w600),
  'formula': TextStyle(color: palette.info),
  'section': TextStyle(color: palette.accent, fontWeight: FontWeight.w700),
  'name': TextStyle(color: palette.error),
  'selector-tag': TextStyle(color: palette.error),
  'deletion': TextStyle(color: palette.error),
  'subst': TextStyle(color: palette.error),
  'literal': TextStyle(color: palette.accent),
  'string': TextStyle(color: palette.success),
  'regexp': TextStyle(color: palette.success),
  'addition': TextStyle(color: palette.success),
  'attribute': TextStyle(color: palette.success),
  'meta-string': TextStyle(color: palette.success),
  'attr': TextStyle(color: palette.warning),
  'variable': TextStyle(color: palette.warning),
  'template-variable': TextStyle(color: palette.warning),
  'type': TextStyle(color: palette.warning),
  'selector-class': TextStyle(color: palette.warning),
  'selector-attr': TextStyle(color: palette.warning),
  'selector-pseudo': TextStyle(color: palette.warning),
  'number': TextStyle(color: palette.warning),
  'symbol': TextStyle(color: palette.info),
  'bullet': TextStyle(color: palette.info),
  'link': TextStyle(color: palette.info),
  'meta': TextStyle(color: palette.accentMuted),
  'selector-id': TextStyle(color: palette.info),
  'title': TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
  'built_in': TextStyle(color: palette.info),
  'title.class_': TextStyle(color: palette.warning),
  'class-title': TextStyle(color: palette.warning),
  'params': TextStyle(color: palette.textSecondary),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
  // Robot-specific aliases from langRobot (section/keyword/variable/string…)
  ...robotHighlightTheme(palette.brightness),
};

Highlight? _sharedHighlightEngine;

Highlight _sharedHighlight() {
  final existing = _sharedHighlightEngine;
  if (existing != null) return existing;
  final highlight = Highlight()..registerLanguage('robot', langRobot);
  final python = builtinAllLanguages['python'];
  if (python != null) {
    highlight.registerLanguage('python', python);
  }
  _sharedHighlightEngine = highlight;
  return highlight;
}

TextStyle _defaultHighlightBase(AppPalette palette) => TextStyle(
  fontFamily: 'Menlo',
  fontSize: 13,
  height: 1.45,
  letterSpacing: 0,
  wordSpacing: 0,
  color: palette.textPrimary,
);

void _ensureLanguageRegistered(String id, Mode mode) {
  _sharedHighlight().registerLanguage(id, mode);
}

/// Highlight source with a registered language and the editor token theme.
TextSpan highlightSource(
  String code,
  AppPalette palette, {
  required String language,
  TextStyle? base,
}) {
  final baseStyle = base ?? _defaultHighlightBase(palette);
  if (code.isEmpty) {
    return TextSpan(text: '', style: baseStyle);
  }
  try {
    final result = _sharedHighlight().highlight(code: code, language: language);
    final renderer = TextSpanRenderer(baseStyle, editorHighlightTheme(palette));
    result.render(renderer);
    return renderer.span ?? TextSpan(text: code, style: baseStyle);
  } catch (_) {
    return TextSpan(text: code, style: baseStyle);
  }
}

/// Highlight [code] using the same grammar mapping as the code editor.
///
/// Unknown extensions fall back to a plain [TextSpan] (no tokens).
TextSpan highlightSourceForPath(
  String code,
  String path,
  AppPalette palette, {
  TextStyle? base,
}) {
  final baseStyle = base ?? _defaultHighlightBase(palette);
  final resolved = _resolveLanguage(path);
  if (resolved == null) {
    return TextSpan(text: code, style: baseStyle);
  }
  _ensureLanguageRegistered(resolved.id, resolved.mode);
  return highlightSource(code, palette, language: resolved.id, base: baseStyle);
}

/// Flatten [root] and split on newlines into [expectedLineCount] line spans.
///
/// Used by the Git diff viewer so each side can be highlighted as one buffer
/// (better grammar context) then rendered row-by-row.
@visibleForTesting
List<TextSpan> splitTextSpanByNewlines(
  TextSpan root, {
  required int expectedLineCount,
  TextStyle? base,
}) {
  if (expectedLineCount <= 0) return const [];

  final runs = <({String text, TextStyle? style})>[];
  void walk(InlineSpan span, TextStyle? inherited) {
    final style = span.style == null
        ? inherited
        : (inherited?.merge(span.style) ?? span.style);
    if (span is! TextSpan) return;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      runs.add((text: text, style: style));
    }
    final children = span.children;
    if (children == null) return;
    for (final child in children) {
      walk(child, style);
    }
  }

  walk(root, root.style ?? base);

  final lines = <TextSpan>[];
  var current = <InlineSpan>[];

  void flush() {
    if (current.isEmpty) {
      lines.add(TextSpan(text: '', style: base ?? root.style));
    } else {
      lines.add(
        TextSpan(
          style: base ?? root.style,
          children: List<InlineSpan>.of(current),
        ),
      );
    }
    current = <InlineSpan>[];
  }

  for (final run in runs) {
    final parts = run.text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) flush();
      if (parts[i].isEmpty) continue;
      current.add(TextSpan(text: parts[i], style: run.style));
    }
  }
  flush();

  while (lines.length < expectedLineCount) {
    lines.add(TextSpan(text: '', style: base ?? root.style));
  }
  if (lines.length > expectedLineCount) {
    return lines.sublist(0, expectedLineCount);
  }
  return lines;
}

/// Highlight [lineTexts] joined as one buffer, then split back into rows.
List<TextSpan> highlightLinesForPath(
  List<String> lineTexts,
  String path,
  AppPalette palette, {
  TextStyle? base,
}) {
  final baseStyle = base ?? _defaultHighlightBase(palette);
  if (lineTexts.isEmpty) return const [];
  final span = highlightSourceForPath(
    lineTexts.join('\n'),
    path,
    palette,
    base: baseStyle,
  );
  return splitTextSpanByNewlines(
    span,
    expectedLineCount: lineTexts.length,
    base: baseStyle,
  );
}

/// Highlight Robot Framework source with the same theme as the editor.
///
/// Used by Library docs example blocks so they match open `.robot` tabs.
TextSpan highlightRobotSource(
  String code,
  AppPalette palette, {
  TextStyle? base,
}) => highlightSource(code, palette, language: 'robot', base: base);

/// Highlight a keyword argument label from libdoc / ArgInfo.
///
/// Libdoc emits Python-style typed signatures (`name: str | None = None`) for
/// library keywords — those get a dedicated signature highlighter so custom
/// types (`WebElement`), unions, and unquoted defaults are colored. Robot
/// variable forms (`${path}`, `@{args}`) keep the Robot grammar.
TextSpan highlightKeywordArgument(
  String label,
  AppPalette palette, {
  TextStyle? base,
}) {
  final baseStyle =
      base ??
      TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: palette.textPrimary,
      );
  if (label.isEmpty) {
    return TextSpan(text: '', style: baseStyle);
  }
  if (_argumentHighlightLanguage(label) == 'robot') {
    return highlightRobotSource(label, palette, base: baseStyle);
  }
  return _highlightTypedArgument(label, palette, baseStyle);
}

@visibleForTesting
String argumentHighlightLanguage(String label) =>
    _argumentHighlightLanguage(label);

String _argumentHighlightLanguage(String label) {
  if (RegExp(r'[\$@&%]\{').hasMatch(label)) return 'robot';
  return 'typed';
}

/// VS Code-like colors for `name: Type | Other = default` libdoc labels.
TextSpan _highlightTypedArgument(
  String label,
  AppPalette palette,
  TextStyle base,
) {
  final theme = robotHighlightTheme(palette.brightness);
  TextStyle token(String role, [TextStyle? extra]) {
    final roleStyle = theme[role];
    return base.merge(roleStyle).merge(extra);
  }

  final nameStyle = token(
    'variable',
    const TextStyle(fontWeight: FontWeight.w600),
  );
  final typeStyle = token('built_in');
  final literalStyle = token('keyword');
  final stringStyle = token('string');
  final numberStyle = token('number');
  final punctStyle = base.merge(TextStyle(color: palette.textSecondary));

  final children = <InlineSpan>[];
  var i = 0;

  void emit(String text, TextStyle style) {
    if (text.isEmpty) return;
    children.add(TextSpan(text: text, style: style));
  }

  // Leading * / ** (varargs / kwargs).
  if (label.startsWith('**')) {
    emit('**', punctStyle);
    i = 2;
  } else if (label.startsWith('*')) {
    emit('*', punctStyle);
    i = 1;
  }

  // Parameter name.
  final nameMatch = RegExp(r'[A-Za-z_][\w]*').matchAsPrefix(label, i);
  if (nameMatch == null) {
    emit(label.substring(i), base);
    return TextSpan(style: base, children: children);
  }
  emit(nameMatch.group(0)!, nameStyle);
  i = nameMatch.end;

  // Optional `: type`
  if (i < label.length && label[i] == ':') {
    emit(':', punctStyle);
    i++;
    while (i < label.length && label[i] == ' ') {
      emit(' ', base);
      i++;
    }
    // Type runs until top-level ` = ` (spaces around =).
    final typeEnd = _topLevelDefaultEquals(label, i);
    _emitTypeExpression(
      label.substring(i, typeEnd),
      emit: emit,
      typeStyle: typeStyle,
      literalStyle: literalStyle,
      punctStyle: punctStyle,
      base: base,
    );
    i = typeEnd;
  }

  // Optional ` = default`
  final eq = RegExp(r'\s*=\s*').matchAsPrefix(label, i);
  if (eq != null) {
    emit(eq.group(0)!, punctStyle);
    i = eq.end;
    final defaultText = label.substring(i);
    emit(
      defaultText,
      _defaultStyle(defaultText, literalStyle, stringStyle, numberStyle, base),
    );
  } else if (i < label.length) {
    emit(label.substring(i), base);
  }

  return TextSpan(style: base, children: children);
}

/// Index of the `=` that starts a default value, or [length] if none.
///
/// Ignores `=` inside `[…]` generics (unusual) and requires the `=` to be a
/// default separator — libdoc uses `name: T = value`.
int _topLevelDefaultEquals(String label, int start) {
  var depth = 0;
  for (var i = start; i < label.length; i++) {
    final ch = label[i];
    if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      if (depth > 0) depth--;
    } else if (ch == '=' && depth == 0) {
      // Prefer ` = ` form; also accept bare `=` after the type.
      return i;
    }
  }
  return label.length;
}

void _emitTypeExpression(
  String typeExpr, {
  required void Function(String text, TextStyle style) emit,
  required TextStyle typeStyle,
  required TextStyle literalStyle,
  required TextStyle punctStyle,
  required TextStyle base,
}) {
  final ident = RegExp(r'[A-Za-z_][\w]*');
  var i = 0;
  while (i < typeExpr.length) {
    final ch = typeExpr[i];
    if (ch == ' ' ||
        ch == '|' ||
        ch == '[' ||
        ch == ']' ||
        ch == ',' ||
        ch == '.' ||
        ch == ':') {
      emit(ch, punctStyle);
      i++;
      continue;
    }
    final m = ident.matchAsPrefix(typeExpr, i);
    if (m != null) {
      final word = m.group(0)!;
      emit(word, _isLiteralName(word) ? literalStyle : typeStyle);
      i = m.end;
      continue;
    }
    emit(ch, base);
    i++;
  }
}

bool _isLiteralName(String word) {
  switch (word) {
    case 'None':
    case 'True':
    case 'False':
    case 'Ellipsis':
    case '...':
      return true;
    default:
      return false;
  }
}

TextStyle _defaultStyle(
  String value,
  TextStyle literalStyle,
  TextStyle stringStyle,
  TextStyle numberStyle,
  TextStyle base,
) {
  final trimmed = value.trim();
  if (_isLiteralName(trimmed)) return literalStyle;
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return numberStyle;
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return stringStyle;
  }
  // Libdoc often omits quotes on string defaults (file names, CSS, etc.).
  if (trimmed.isNotEmpty) return stringStyle;
  return base;
}
