import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ToolbarButton extends StatefulWidget {
  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.danger = false,
    this.showLabel = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool showLabel;
  final String? tooltip;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final primary = widget.primary;
    final danger = widget.danger && enabled;
    final bg = !enabled
        ? (primary
            ? AppColors.accent.withValues(alpha: 0.22)
            : Colors.transparent)
        : primary
            ? AppColors.accent
            : danger && _hovered
                ? AppColors.error.withValues(alpha: 0.12)
                : _hovered
                    ? AppColors.surfaceHover
                    : Colors.transparent;
    final fg = !enabled
        ? AppColors.textMuted.withValues(alpha: 0.55)
        : primary
            ? const Color(0xFFE8F2F2)
            : danger
                ? AppColors.error
                : AppColors.textPrimary;
    final borderColor = !enabled
        ? (primary || danger
            ? AppColors.border.withValues(alpha: 0.35)
            : Colors.transparent)
        : primary
            ? Colors.transparent
            : danger
                ? AppColors.error.withValues(alpha: _hovered ? 0.55 : 0.35)
                : (_hovered ? AppColors.border : AppColors.border.withValues(alpha: 0.5));

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: widget.showLabel ? 12 : 8,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 15, color: fg),
          if (widget.showLabel) ...[
            const SizedBox(width: 6),
            Text(
              widget.label.toUpperCase(),
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: widget.tooltip ?? widget.label,
      child: MouseRegion(
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: child,
        ),
      ),
    );
  }
}
