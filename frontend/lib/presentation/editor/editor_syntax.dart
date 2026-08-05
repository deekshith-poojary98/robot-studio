import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../core/theme/app_theme.dart';
import 'robot_language.dart';

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
