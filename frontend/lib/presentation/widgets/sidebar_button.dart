import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SidebarButton extends StatefulWidget {
  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final color = active
        ? context.palette.accent
        : _hovered
        ? context.palette.textPrimary
        : context.palette.textSecondary;

    return Tooltip(
      message: widget.tooltip ?? widget.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 250),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            // Full rail width so Settings (Column child) matches panel
            // buttons (ListView children, which already stretch to 52).
            width: double.infinity,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? context.palette.accentSoft
                  : _hovered
                  ? context.palette.surfaceHover
                  : Colors.transparent,
              borderRadius: BorderRadius.zero,
              border: active
                  ? Border(
                      top: BorderSide(
                        color: context.palette.accent.withValues(alpha: 0.22),
                      ),
                      bottom: BorderSide(
                        color: context.palette.accent.withValues(alpha: 0.22),
                      ),
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
