import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/theme/app_theme.dart';

/// Find / replace panel styled for Robot Studio (includes whole-word via regex).
class EditorFindPanel extends StatefulWidget implements PreferredSizeWidget {
  const EditorFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final CodeFindController controller;
  final bool readOnly;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    final height = value.replaceMode ? 84.0 : 42.0;
    return Size(double.infinity, height);
  }

  @override
  State<EditorFindPanel> createState() => _EditorFindPanelState();
}

class _EditorFindPanelState extends State<EditorFindPanel> {
  bool _wholeWord = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();

    final result = value.result;
    final resultLabel = result == null
        ? 'none'
        : '${result.index + 1}/${result.matches.length}';

    return Container(
      alignment: Alignment.topRight,
      padding: const EdgeInsets.only(right: 10, top: 4),
      color: AppColors.surfaceElevated,
      child: SizedBox(
        width: 420,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Find',
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                    onChanged: (_) => _syncOptions(),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  resultLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                _Toggle(
                  label: 'Aa',
                  selected: value.option.caseSensitive,
                  onTap: () {
                    controller.toggleCaseSensitive();
                    setState(() {});
                  },
                ),
                _Toggle(
                  label: '.*',
                  selected: value.option.regex && !_wholeWord,
                  onTap: () {
                    _wholeWord = false;
                    controller.toggleRegex();
                    setState(() {});
                  },
                ),
                _Toggle(
                  label: 'W',
                  selected: _wholeWord,
                  onTap: () {
                    setState(() => _wholeWord = !_wholeWord);
                    _syncOptions();
                  },
                ),
                IconButton(
                  tooltip: 'Previous',
                  onPressed:
                      result == null ? null : controller.previousMatch,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: result == null ? null : controller.nextMatch,
                  icon: const Icon(Icons.arrow_downward, size: 16),
                ),
                IconButton(
                  tooltip: value.replaceMode ? 'Hide Replace' : 'Replace',
                  onPressed: widget.readOnly
                      ? null
                      : () {
                          if (value.replaceMode) {
                            controller.findMode();
                          } else {
                            controller.replaceMode();
                          }
                          setState(() {});
                        },
                  icon: const Icon(Icons.find_replace, size: 16),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: controller.close,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
            if (value.replaceMode && !widget.readOnly)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.replaceInputController,
                      focusNode: controller.replaceInputFocusNode,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Replace',
                        filled: true,
                        fillColor: AppColors.surface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Replace',
                    onPressed:
                        result == null ? null : controller.replaceMatch,
                    icon: const Icon(Icons.done, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Replace All',
                    onPressed:
                        result == null ? null : controller.replaceAllMatches,
                    icon: const Icon(Icons.done_all, size: 16),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _syncOptions() {
    if (!_wholeWord) return;
    final raw = widget.controller.findInputController.text;
    if (raw.isEmpty) return;
    final escaped = RegExp.escape(raw);
    final value = widget.controller.value;
    if (value == null) return;
    widget.controller.value = value.copyWith(
      option: value.option.copyWith(
        pattern: '\\b$escaped\\b',
        regex: true,
      ),
      result: value.result,
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
