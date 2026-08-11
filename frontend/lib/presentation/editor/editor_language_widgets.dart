import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

class RobotAutocompletePromptsBuilder
    implements CodeAutocompletePromptsBuilder {
  RobotAutocompletePromptsBuilder(this.items, {this.signature});

  List<CompletionItemInfo> items;
  SignatureHelpInfo? signature;

  void update(List<CompletionItemInfo> next, {SignatureHelpInfo? signature}) {
    items = next;
    this.signature = signature;
  }

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final lineText = codeLine.text;
    final offset = selection.baseOffset;
    final prefix = _prefixAt(lineText, offset);
    final inArgs = isArgumentSlot(lineText, offset, signature);
    final typingValue = isTypingNamedArgValue(lineText, offset);

    var candidates = <CompletionItemInfo>[
      if (inArgs && !typingValue)
        ...namedArgsFromSignature(lineText, offset, signature),
      ...items,
    ];
    candidates = _dedupeByInsert(candidates);

    if (typingValue) {
      // Still inside this cell's value (e.g. expression=random.randint( )).
      // Next-arg ``name=`` inserts belong at a 2-space separator, not here.
      candidates = [
        for (final item in candidates)
          if (item.kind != 'parameter') item,
      ];
      if (prefix.isEmpty || candidates.isEmpty) return null;
    } else if (inArgs) {
      final params = [
        for (final item in candidates)
          if (item.kind == 'parameter') item,
      ];
      if (params.isNotEmpty &&
          (prefix.isEmpty || _looksLikeParamPrefix(prefix))) {
        candidates = params;
      }
    } else if (prefix.isEmpty && candidates.length > 20) {
      return null;
    }
    if (candidates.isEmpty) return null;

    final prompts = candidates
        .where((item) => prefix.isEmpty || _labelMatches(item, prefix))
        .map((item) {
          final rawInsert = item.insertText;
          // Continuation lines of snippets are relative to column 0; prepend the
          // current line indent so FOR/IF bodies nest under the suite indent.
          final insert = indentMultilineInsert(
            rawInsert,
            leadingIndentOf(lineText),
          );
          final caret = item.kind == 'parameter' && insert.endsWith('=')
              ? insert.length
              : insert.length;
          // Popup rows are fixed-height single-line; never put multi-line
          // insert_text in [word] or snippets overlap (FOR … Log … END).
          final display = item.label.trim().isNotEmpty
              ? item.label
              : rawInsert.split('\n').first;
          return CodeFieldPrompt(
            word: display,
            type: item.kind,
            customAutocomplete: CodeAutocompleteResult(
              input: prefix,
              word: insert,
              selection: TextSelection.collapsed(offset: caret),
            ),
          );
        })
        .toList();
    if (prompts.isEmpty) return null;
    return CodeAutocompleteEditingValue(
      input: prefix,
      prompts: prompts,
      index: 0,
    );
  }

  /// Case-insensitive prefix / word-start match (not substring — ``a`` ≠ ``RANGE``).
  static bool _labelMatches(CompletionItemInfo item, String prefix) {
    final p = prefix.toLowerCase();
    final label = item.label.toLowerCase();
    if (label.startsWith(p)) return true;
    for (final part in label.split(RegExp(r'[\s.]+'))) {
      if (part.isNotEmpty && part.startsWith(p)) return true;
    }
    return false;
  }

  /// Visible for tests — extracts the autocomplete replace prefix.
  @visibleForTesting
  static String prefixAt(String line, int offset) {
    if (offset <= 0 || offset > line.length) {
      offset = line.length;
    }
    final before = line.substring(0, offset);
    // Section headers: "*** Key" must replace the whole "*** Key", not only "Key".
    final section = RegExp(r'\*{1,3}[\w\s]*$').firstMatch(before);
    if (section != null) {
      return section.group(0)!;
    }
    // Local settings: "[Doc" → "[Documentation]"
    final bracket = RegExp(r'\[[\w\s]*$').firstMatch(before);
    if (bracket != null) {
      return bracket.group(0)!;
    }
    final match = RegExp(r'[\w${}@&][\w\s${}@&.-]*$').firstMatch(before);
    return match?.group(0)?.trim() ?? '';
  }

  /// Leading spaces/tabs of [line] (suite/test body indent).
  @visibleForTesting
  static String leadingIndentOf(String line) {
    final match = RegExp(r'^[ \t]*').firstMatch(line);
    return match?.group(0) ?? '';
  }

  /// Apply [baseIndent] to every line after the first in a multi-line snippet.
  @visibleForTesting
  static String indentMultilineInsert(String insert, String baseIndent) {
    if (baseIndent.isEmpty || !insert.contains('\n')) return insert;
    final lines = insert.split('\n');
    final buffer = StringBuffer(lines.first);
    for (var i = 1; i < lines.length; i++) {
      buffer
        ..write('\n')
        ..write(baseIndent)
        ..write(lines[i]);
    }
    return buffer.toString();
  }

  String _prefixAt(String line, int offset) => prefixAt(line, offset);

  static List<CompletionItemInfo> _dedupeByInsert(
    List<CompletionItemInfo> items,
  ) {
    final seen = <String>{};
    final out = <CompletionItemInfo>[];
    for (final item in items) {
      final key = (item.insertText.isEmpty ? item.label : item.insertText)
          .toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(item);
    }
    return out;
  }

  static bool _looksLikeParamPrefix(String prefix) {
    if (prefix.startsWith(r'${') ||
        prefix.startsWith(r'@{') ||
        prefix.startsWith('*') ||
        prefix.startsWith('[')) {
      return false;
    }
    return RegExp(r'^[A-Za-z_][\w]*$').hasMatch(prefix);
  }

  /// Caret is in an argument cell of a keyword call (not on the keyword name).
  @visibleForTesting
  static bool isArgumentSlot(
    String line,
    int offset,
    SignatureHelpInfo? signature,
  ) {
    if (signature == null || signature.parameters.isEmpty) return false;
    if (!(line.startsWith(' ') || line.startsWith('\t'))) return false;
    final before = line.substring(0, offset.clamp(0, line.length));
    return RegExp(r'[ \t]{2,}|\t').hasMatch(before.trimLeft());
  }

  /// Caret is inside the current argument cell — a value, not a new ``name=``.
  @visibleForTesting
  static bool isTypingNamedArgValue(String line, int offset) {
    final cell = _currentArgumentCell(line, offset);
    if (cell.isEmpty) return false;
    if (_namedArgName(cell) != null) return true;
    return !_looksLikeParamPrefix(cell.trim());
  }

  static String _currentArgumentCell(String line, int offset) {
    final before = line.substring(0, offset.clamp(0, line.length));
    if (RegExp(r'(?:[ \t]{2,}|\t)$').hasMatch(before)) return '';
    final cells = before
        .trimLeft()
        .split(RegExp(r'[ \t]{2,}|\t+'))
        .where((cell) => cell.isNotEmpty)
        .toList();
    return cells.isEmpty ? '' : cells.last;
  }

  /// ``name=`` inserts from the open signature card — available before the
  /// completion round-trip, so the next-arg popup is not intermittent.
  @visibleForTesting
  static List<CompletionItemInfo> namedArgsFromSignature(
    String line,
    int offset,
    SignatureHelpInfo? signature,
  ) {
    if (signature == null || signature.parameters.isEmpty) return const [];
    final filled = _filledArgumentCells(line, offset);
    final present = <String>{};
    var positionalUsed = 0;
    for (final cell in filled) {
      final name = _namedArgName(cell);
      if (name != null) {
        present.add(name.toLowerCase());
      } else if (cell.trim().isNotEmpty) {
        positionalUsed++;
      }
    }

    final consumed = <String>{...present};
    var skippedPositional = 0;
    for (final param in signature.parameters) {
      if (param.kind == 'var_positional') continue;
      final name = _parameterName(param);
      if (name.isEmpty) continue;
      if (consumed.contains(name.toLowerCase())) continue;
      final keywordOnly =
          param.kind == 'keyword_only' || param.kind == 'var_keyword';
      if (!keywordOnly && skippedPositional < positionalUsed) {
        skippedPositional++;
        consumed.add(name.toLowerCase());
      }
    }

    final ranked = List<SignatureParameterInfo>.from(signature.parameters);
    final active = signature.activeParameter.clamp(0, ranked.length - 1);
    if (ranked.isNotEmpty) {
      ranked.insert(0, ranked.removeAt(active));
    }

    final out = <CompletionItemInfo>[];
    for (final param in ranked) {
      if (param.kind == 'var_positional') continue;
      final name = _parameterName(param);
      if (name.isEmpty || consumed.contains(name.toLowerCase())) continue;
      out.add(
        CompletionItemInfo(
          label: '$name=',
          kind: 'parameter',
          detail: param.required ? 'required' : 'optional',
          documentation: param.documentation,
          insertText: '$name=',
          provider: 'signature',
        ),
      );
    }
    return out;
  }

  static List<String> _filledArgumentCells(String line, int offset) {
    final before = line.substring(0, offset.clamp(0, line.length));
    final cells = before
        .trimLeft()
        .split(RegExp(r'[ \t]{2,}|\t+'))
        .where((cell) => cell.isNotEmpty)
        .toList();
    if (cells.isEmpty) return const [];
    var keywordIndex = 0;
    if (RegExp(r'^[\$@&%]').hasMatch(cells.first) && cells.length > 1) {
      keywordIndex = 1;
    }
    if (cells.length <= keywordIndex + 1) return const [];
    final args = cells.sublist(keywordIndex + 1);
    final trailingSep = RegExp(r'(?:[ \t]{2,}|\t)$').hasMatch(before);
    if (trailingSep) return args;
    return args.length <= 1 ? const [] : args.sublist(0, args.length - 1);
  }

  static String? _namedArgName(String cell) {
    final text = cell.trim();
    if (text.isEmpty || !text.contains('=')) return null;
    if (RegExp(r'^[\$@&%]').hasMatch(text)) return null;
    final name = text.split('=').first.trim();
    if (name.isEmpty || name.contains(' ')) return null;
    return name;
  }

  static String _parameterName(SignatureParameterInfo param) {
    if (param.name.trim().isNotEmpty) return param.name.trim();
    final label = param.label.trim();
    if (label.isEmpty) return '';
    return label.split('=').first.split(':').first.trim();
  }
}

class RobotAutocompleteListView extends StatefulWidget
    implements PreferredSizeWidget {
  const RobotAutocompleteListView({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  static const itemHeight = 26.0;

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize =>
      Size(320, (itemHeight * notifier.value.prompts.length.clamp(1, 8)) + 2);

  @override
  State<RobotAutocompleteListView> createState() =>
      _RobotAutocompleteListViewState();
}

class _RobotAutocompleteListViewState extends State<RobotAutocompleteListView> {
  @override
  void initState() {
    widget.notifier.addListener(_refresh);
    super.initState();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier.value;
    return Material(
      elevation: 6,
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: BoxConstraints.loose(widget.preferredSize),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: value.prompts.length,
          itemBuilder: (context, index) {
            final prompt = value.prompts[index];
            final selected = index == value.index;
            return InkWell(
              onTap: () =>
                  widget.onSelected(value.copyWith(index: index).autocomplete),
              child: Container(
                height: RobotAutocompleteListView.itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: selected ? context.palette.accentSoft : null,
                alignment: Alignment.centerLeft,
                child: Text(
                  prompt.word.replaceAll('\n', ' '),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: selected
                        ? context.palette.textPrimary
                        : context.palette.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

TextSpan buildDiagnosticLineSpan({
  required BuildContext context,
  required int lineNumber,
  required CodeLine codeLine,
  required TextSpan textSpan,
  required TextStyle style,
  required List<DiagnosticInfo> diagnostics,
}) {
  final lineDiagnostics = diagnostics
      .where((item) => item.line == lineNumber)
      .toList();
  if (lineDiagnostics.isEmpty) {
    return textSpan;
  }
  final severity = lineDiagnostics.first.severity;
  final color = switch (severity) {
    DiagnosticSeverity.error => context.palette.error,
    DiagnosticSeverity.warning => context.palette.warning,
    DiagnosticSeverity.information => context.palette.accent,
  };
  return TextSpan(
    style: style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: color,
      decorationStyle: TextDecorationStyle.wavy,
    ),
    children: [textSpan],
  );
}
