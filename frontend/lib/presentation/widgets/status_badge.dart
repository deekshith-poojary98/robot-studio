import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.dotColor,
    this.filled = false,
    this.height,
    this.showChevron = false,
  });

  final String label;
  final Color? dotColor;
  final bool filled;

  /// Opt-in fixed height, for rows that must line up with taller neighbours
  /// (the toolbar strip). Left null, the badge hugs its label as before.
  final double? height;

  /// Trailing dropdown arrow — used for interactive toolbar selectors.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: height == null ? null : Alignment.center,
      padding: height == null
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: filled
            ? context.palette.accentSoft
            : context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
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
              color: filled
                  ? context.palette.accent
                  : context.palette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: context.palette.textMuted,
            ),
          ],
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
    this.height,
    this.showChevron = false,
  });

  final String label;
  final bool active;
  final bool broken;
  final double? height;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final Color? dot;
    if (broken) {
      dot = context.palette.warning;
    } else if (active) {
      dot = context.palette.accent;
    } else {
      dot = context.palette.textMuted;
    }
    return StatusBadge(
      label: label,
      dotColor: dot,
      filled: active && !broken,
      height: height,
      showChevron: showChevron,
    );
  }
}
