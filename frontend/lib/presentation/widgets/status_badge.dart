import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.dotColor,
    this.filled = false,
  });

  final String label;
  final Color? dotColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? AppColors.accentSoft : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? AppColors.accent : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class EnvironmentBadge extends StatelessWidget {
  const EnvironmentBadge({
    super.key,
    required this.label,
    this.active = false,
    this.broken = false,
  });

  final String label;
  final bool active;
  final bool broken;

  @override
  Widget build(BuildContext context) {
    final Color? dot;
    if (broken) {
      dot = AppColors.warning;
    } else if (active) {
      dot = AppColors.accent;
    } else {
      dot = AppColors.textMuted;
    }
    return StatusBadge(
      label: label,
      dotColor: dot,
      filled: active && !broken,
    );
  }
}
