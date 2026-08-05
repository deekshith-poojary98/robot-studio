import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

class RobotAutocompletePromptsBuilder
    implements CodeAutocompletePromptsBuilder {
  RobotAutocompletePromptsBuilder(this.items);

  List<CompletionItemInfo> items;

  void update(List<CompletionItemInfo> next) {
    items = next;
  }

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (items.isEmpty) return null;
    final lineText = codeLine.text;
    final offset = selection.baseOffset;
    final prefix = _prefixAt(lineText, offset);
    if (prefix.isEmpty && items.length > 20) return null;

    final prompts = items
        .where((item) => prefix.isEmpty || _labelMatches(item, prefix))
        .map((item) {
          final insert = item.insertText;
          final caret = item.kind == 'parameter' && insert.endsWith('=')
              ? insert.length
              : insert.length;
          return CodeFieldPrompt(
            word: insert,
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

  String _prefixAt(String line, int offset) => prefixAt(line, offset);
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
                  prompt.word,
                  style: TextStyle(
                    fontSize: 12,
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
