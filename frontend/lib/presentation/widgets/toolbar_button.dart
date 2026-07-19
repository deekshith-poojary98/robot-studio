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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool showLabel;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? AppColors.accent
        : _hovered
            ? AppColors.surfaceHover
            : Colors.transparent;
    final fg = widget.primary
        ? const Color(0xFFE8F2F2)
        : widget.danger
            ? AppColors.error
            : AppColors.textPrimary;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.symmetric(
        horizontal: widget.showLabel ? 12 : 8,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: widget.primary
            ? null
            : Border.all(color: _hovered ? AppColors.border : Colors.transparent),
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
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: child,
        ),
      ),
    );
  }
}
