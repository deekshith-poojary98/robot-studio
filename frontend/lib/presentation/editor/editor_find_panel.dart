import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/theme/app_theme.dart';

/// Find / replace widget styled for Robot Studio.
///
/// re_editor stacks this on top of the editor field as a non-positioned child,
/// so the root must size itself to the panel (an expanding box would paint over
/// the whole document).
///
/// Whole-word is not a first-class [CodeFindOption] flag — when enabled we wrap
/// the pattern in `\b…\b` (and force regex mode for the search). The text field
/// always shows the user's raw query.
class EditorFindPanel extends StatefulWidget implements PreferredSizeWidget {
  const EditorFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final CodeFindController controller;
  final bool readOnly;

  static const _fieldHeight = 30.0;
  static const _rowGap = 6.0;
  static const _boxPadding = 6.0;
  static const _topMargin = 6.0;

  /// Reserved as editor top padding, so the find box never hides line 1.
  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    final rows = value.replaceMode && !readOnly ? 2 : 1;
    final height = _topMargin +
        _boxPadding * 2 +
        rows * _fieldHeight +
        (rows - 1) * _rowGap;
    return Size(double.infinity, height);
  }

  /// Pattern actually handed to re_editor for the given raw query + flags.
  @visibleForTesting
  static String effectivePattern(
    String raw, {
    required bool wholeWord,
    required bool regex,
  }) {
    if (!wholeWord || raw.isEmpty) return raw;
    if (regex) return '\\b(?:$raw)\\b';
    return '\\b${RegExp.escape(raw)}\\b';
  }

  @override
  State<EditorFindPanel> createState() => _EditorFindPanelState();
}

class _EditorFindPanelState extends State<EditorFindPanel> {
  /// User's regex preference (independent of whole-word forcing regex:true).
  bool _regex = false;
  bool _wholeWord = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _regex = widget.controller.value?.option.regex ?? false;
    widget.controller.findInputController.addListener(_onFindTextChanged);
  }

  @override
  void dispose() {
    widget.controller.findInputController.removeListener(_onFindTextChanged);
    super.dispose();
  }

  void _onFindTextChanged() {
    if (_applying || !_wholeWord) return;
    // re_editor just copied the raw text into option.pattern — re-wrap after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _wholeWord && !_applying) {
        _applySearchOptions();
      }
    });
  }

  void _toggleRegex() {
    setState(() => _regex = !_regex);
    if (_wholeWord) {
      _applySearchOptions();
    } else {
      widget.controller.toggleRegex();
    }
  }

  void _toggleWholeWord() {
    setState(() => _wholeWord = !_wholeWord);
    _applySearchOptions();
  }

  void _applySearchOptions() {
    final controller = widget.controller;
    final value = controller.value;
    if (value == null) return;

    final raw = controller.findInputController.text;
    final pattern = EditorFindPanel.effectivePattern(
      raw,
      wholeWord: _wholeWord,
      regex: _regex,
    );
    // Whole-word wraps need the regex engine; otherwise honor the user's toggle.
    final regex = (_wholeWord && raw.isNotEmpty) ? true : _regex;

    if (value.option.pattern == pattern && value.option.regex == regex) {
      return;
    }

    _applying = true;
    controller.value = value.copyWith(
      option: value.option.copyWith(pattern: pattern, regex: regex),
      result: null,
      searching: true,
    );
    // re_editor only re-runs find from private `_updateResult`; public option
    // toggles call it. Bounce match-case so the wrapped pattern is searched
    // without permanently flipping the user's case flag.
    controller.toggleCaseSensitive();
    controller.toggleCaseSensitive();
    _applying = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();

    final result = value.result;
    final resultLabel = result == null
        ? 'No results'
        : '${result.index + 1} of ${result.matches.length}';
    final showReplace = value.replaceMode && !widget.readOnly;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(
          right: 18,
          top: EditorFindPanel._topMargin,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): controller.close,
          },
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(EditorFindPanel._boxPadding),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: EditorFindPanel._fieldHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: _Field(
                          controller: controller.findInputController,
                          focusNode: controller.findInputFocusNode,
                          hint: 'Find',
                          onSubmitted: _submitFind,
                          suffix: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Toggle(
                                label: 'Aa',
                                tooltip: 'Match Case',
                                selected: value.option.caseSensitive,
                                onTap: controller.toggleCaseSensitive,
                              ),
                              _Toggle(
                                label: 'ab',
                                tooltip: 'Match Whole Word',
                                selected: _wholeWord,
                                onTap: _toggleWholeWord,
                              ),
                              _Toggle(
                                label: '.*',
                                tooltip: 'Use Regular Expression',
                                selected: _regex,
                                onTap: _toggleRegex,
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 78,
                        child: Text(
                          resultLabel,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      _IconAction(
                        icon: Icons.arrow_upward,
                        tooltip: 'Previous Match (Shift+Enter)',
                        onPressed:
                            result == null ? null : controller.previousMatch,
                      ),
                      _IconAction(
                        icon: Icons.arrow_downward,
                        tooltip: 'Next Match (Enter)',
                        onPressed: result == null ? null : controller.nextMatch,
                      ),
                      _IconAction(
                        icon: Icons.find_replace,
                        tooltip: showReplace ? 'Hide Replace' : 'Replace',
                        selected: showReplace,
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                if (value.replaceMode) {
                                  controller.findMode();
                                } else {
                                  controller.replaceMode();
                                }
                              },
                      ),
                      _IconAction(
                        icon: Icons.close,
                        tooltip: 'Close (Esc)',
                        onPressed: controller.close,
                      ),
                    ],
                  ),
                ),
                if (showReplace) ...[
                  const SizedBox(height: EditorFindPanel._rowGap),
                  SizedBox(
                    height: EditorFindPanel._fieldHeight,
                    child: Row(
                      children: [
                        Expanded(
                          child: _Field(
                            controller: controller.replaceInputController,
                            focusNode: controller.replaceInputFocusNode,
                            hint: 'Replace',
                            onSubmitted: (_) => controller.replaceMatch(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _IconAction(
                          icon: Icons.done,
                          tooltip: 'Replace',
                          onPressed:
                              result == null ? null : controller.replaceMatch,
                        ),
                        _IconAction(
                          icon: Icons.done_all,
                          tooltip: 'Replace All',
                          onPressed: result == null
                              ? null
                              : controller.replaceAllMatches,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitFind(String _) {
    if (widget.controller.value?.result == null) return;
    final shift = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight,
    );
    if (shift) {
      widget.controller.previousMatch();
    } else {
      widget.controller.nextMatch();
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontFamily: 'Menlo',
      ),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minHeight: 22),
        border: _border(AppColors.border),
        enabledBorder: _border(AppColors.border),
        focusedBorder: _border(AppColors.accent),
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: color),
      );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? AppColors.textMuted.withValues(alpha: 0.4)
        : selected
            ? AppColors.accent
            : AppColors.textSecondary;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
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
      ),
    );
  }
}
