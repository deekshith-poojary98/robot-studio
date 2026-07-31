import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

class RobotAutocompletePromptsBuilder implements CodeAutocompletePromptsBuilder {
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
        .map(
          (item) => CodeFieldPrompt(
            word: item.insertText,
            type: item.kind,
            customAutocomplete: CodeAutocompleteResult(
              input: prefix,
              word: item.insertText,
              selection: TextSelection.collapsed(
                offset: item.insertText.length,
              ),
            ),
          ),
        )
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

  String _prefixAt(String line, int offset) {
    if (offset <= 0 || offset > line.length) {
      offset = line.length;
    }
    final before = line.substring(0, offset);
    final match = RegExp(r'[\w${}@&][\w\s${}@&.-]*$').firstMatch(before);
    return match?.group(0)?.trim() ?? '';
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
  Size get preferredSize => Size(
        320,
        (itemHeight * notifier.value.prompts.length.clamp(1, 8)) + 2,
      );

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
      color: AppColors.surface,
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
              onTap: () => widget.onSelected(
                value.copyWith(index: index).autocomplete,
              ),
              child: Container(
                height: RobotAutocompleteListView.itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: selected ? AppColors.accentSoft : null,
                alignment: Alignment.centerLeft,
                child: Text(
                  prompt.word,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
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
  final lineDiagnostics =
      diagnostics.where((item) => item.line == lineNumber).toList();
  if (lineDiagnostics.isEmpty) {
    return textSpan;
  }
  final severity = lineDiagnostics.first.severity;
  final color = switch (severity) {
    DiagnosticSeverity.error => AppColors.error,
    DiagnosticSeverity.warning => AppColors.warning,
    DiagnosticSeverity.information => AppColors.accent,
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
