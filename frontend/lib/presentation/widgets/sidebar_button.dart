import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SidebarButton extends StatefulWidget {
  const SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final color = active
        ? AppColors.accent
        : _hovered
            ? AppColors.textPrimary
            : AppColors.textSecondary;

    return Tooltip(
      message: widget.label,
      preferBelow: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accentSoft
                  : _hovered
                      ? AppColors.surfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: active
                    ? AppColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
