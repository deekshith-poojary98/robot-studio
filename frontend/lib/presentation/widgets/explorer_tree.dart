import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'always_delayed_tooltip.dart';

class ToolSection extends StatefulWidget {
  const ToolSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Widget? trailing;

  @override
  State<ToolSection> createState() => _ToolSectionState();
}

class _ToolSectionState extends State<ToolSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant ToolSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded && !oldWidget.initiallyExpanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 2,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 160),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class ExplorerTreeItem extends StatefulWidget {
  const ExplorerTreeItem({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.indent = 0,
    this.selected = false,
    this.onTap,
    this.onSecondaryTap,
    this.trailing,
    this.tooltip,
    this.semanticLabel,
    this.isEditing = false,
    this.editInitialValue,
    this.onEditSubmit,
    this.onEditCancel,
    this.onEditChanged,
    this.editHint,
    this.suggestion,
    this.onApplySuggestion,
  }) : assert(icon != null || leading != null);

  final String label;
  /// Material icon used when [leading] is null.
  final IconData? icon;
  /// Prefer this for Seti / dynamic file icons (keeps package colors).
  final Widget? leading;
  final int indent;
  final bool selected;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTap;
  final Widget? trailing;
  final String? tooltip;
  final String? semanticLabel;
  final bool isEditing;
  final String? editInitialValue;
  final ValueChanged<String>? onEditSubmit;
  final VoidCallback? onEditCancel;
  final ValueChanged<String>? onEditChanged;
  final String? editHint;
  final String? suggestion;
  final VoidCallback? onApplySuggestion;

  @override
  State<ExplorerTreeItem> createState() => _ExplorerTreeItemState();
}

class _ExplorerTreeItemState extends State<ExplorerTreeItem> {
  bool _hovered = false;
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.editInitialValue ?? widget.label,
    );
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExplorerTreeItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      _controller.text = widget.editInitialValue ?? widget.label;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onEditSubmit?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final row = Semantics(
      button: true,
      selected: selected,
      label: widget.semanticLabel ?? widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onSecondaryTapDown: widget.onSecondaryTap,
          child: InkWell(
            onTap: widget.isEditing ? null : widget.onTap,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + 2,
                vertical: 0,
              ),
              padding: EdgeInsets.only(
                left: AppSpacing.sm + widget.indent * 12.0,
                right: AppSpacing.sm,
                top: 2,
                bottom: 2,
              ),
              decoration: BoxDecoration(
                color: selected || widget.isEditing
                    ? AppColors.accentSoft
                    : _hovered
                        ? AppColors.surfaceHover
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: selected || widget.isEditing
                    ? Border.all(
                        color: AppColors.accent.withValues(alpha: 0.28),
                      )
                    : Border.all(color: Colors.transparent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: widget.leading ??
                            Icon(
                              widget.icon,
                              size: 16,
                              color: selected || widget.isEditing
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: widget.isEditing
                            ? Shortcuts(
                                shortcuts: const {
                                  SingleActivator(LogicalKeyboardKey.escape):
                                      _CancelIntent(),
                                  SingleActivator(LogicalKeyboardKey.enter):
                                      _SubmitIntent(),
                                },
                                child: Actions(
                                  actions: {
                                    _CancelIntent: CallbackAction<_CancelIntent>(
                                      onInvoke: (_) {
                                        widget.onEditCancel?.call();
                                        return null;
                                      },
                                    ),
                                    _SubmitIntent: CallbackAction<_SubmitIntent>(
                                      onInvoke: (_) {
                                        _submit();
                                        return null;
                                      },
                                    ),
                                  },
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5,
                                      height: 1.25,
                                    ),
                                    cursorColor: AppColors.accent,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: widget.editHint,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onSubmitted: (_) => _submit(),
                                    onTapOutside: (_) {
                                      // Defer so sibling actions (e.g. suggestion
                                      // chip) can commit first and clear editing.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted || !widget.isEditing) {
                                          return;
                                        }
                                        _submit();
                                      });
                                    },
                                    onChanged: (value) {
                                      widget.onEditChanged?.call(value);
                                      setState(() {});
                                    },
                                  ),
                                ),
                              )
                            : Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.accent
                                      : AppColors.textPrimary,
                                  fontSize: 12.5,
                                  height: 1.25,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                  if (widget.isEditing &&
                      widget.suggestion != null &&
                      widget.onApplySuggestion != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.accent,
                        ),
                        onPressed: widget.onApplySuggestion,
                        child: Text(
                          'Create ${widget.suggestion}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.isEditing) return row;
    final tip = widget.tooltip;
    if (tip == null || tip.isEmpty) return row;
    // Always wait — Material Tooltip skips waitDuration when moving between
    // open tip targets, which flashes the full path on every row hop.
    return AlwaysDelayedTooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 700),
      child: row,
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}
