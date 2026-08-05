import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Where a button sits inside a [ToolbarButtonGroup].
///
/// Group members drop their own border and outer radius so the group can draw
/// one continuous rectangle with hairline separators instead of gaps.
enum ToolbarButtonPosition { standalone, first, middle, last }

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
    this.position = ToolbarButtonPosition.standalone,
    this.width,
    this.height,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool showLabel;
  final String? tooltip;
  final ToolbarButtonPosition position;

  /// Fixed width — [ToolbarButtonGroup] sets this so every segment matches.
  final double? width;
  final double? height;

  bool get inGroup => position != ToolbarButtonPosition.standalone;

  /// Text style shared with the group's width measurement.
  static const labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  static const iconSize = 15.0;
  static const iconLabelGap = 6.0;
  static const labelPadding = 12.0;
  static const iconOnlyPadding = 8.0;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hovered = false;

  BorderRadius get _radius {
    const corner = Radius.circular(AppRadii.sm);
    return switch (widget.position) {
      ToolbarButtonPosition.standalone => BorderRadius.circular(AppRadii.sm),
      ToolbarButtonPosition.first => const BorderRadius.horizontal(
        left: corner,
      ),
      ToolbarButtonPosition.middle => BorderRadius.zero,
      ToolbarButtonPosition.last => const BorderRadius.horizontal(
        right: corner,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final primary = widget.primary;
    final danger = widget.danger && enabled;
    final bg = !enabled
        ? (primary
              ? context.palette.accent.withValues(alpha: 0.22)
              : Colors.transparent)
        : primary
        ? context.palette.accent
        : danger && _hovered
        ? context.palette.error.withValues(alpha: 0.12)
        : _hovered
        ? context.palette.surfaceHover
        : Colors.transparent;
    final fg = !enabled
        ? context.palette.textMuted.withValues(alpha: 0.55)
        : primary
        ? context.palette.onAccent
        : danger
        ? context.palette.error
        : context.palette.textPrimary;
    // The group paints one shared outline, so members stay borderless.
    final borderColor = widget.inGroup
        ? Colors.transparent
        : !enabled
        ? (primary || danger
              ? context.palette.border.withValues(alpha: 0.35)
              : Colors.transparent)
        : primary
        ? Colors.transparent
        : danger
        ? context.palette.error.withValues(alpha: _hovered ? 0.55 : 0.35)
        : (_hovered
              ? context.palette.border
              : context.palette.border.withValues(alpha: 0.5));

    final radius = _radius;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: widget.width,
      height: widget.height,
      constraints: widget.width == null
          ? const BoxConstraints(minWidth: 30, minHeight: 30)
          : null,
      alignment: Alignment.center,
      padding: widget.width != null
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: widget.showLabel
                  ? ToolbarButton.labelPadding
                  : ToolbarButton.iconOnlyPadding,
              vertical: 7,
            ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: ToolbarButton.iconSize, color: fg),
          if (widget.showLabel) ...[
            const SizedBox(width: ToolbarButton.iconLabelGap),
            Text(
              widget.label.toUpperCase(),
              style: ToolbarButton.labelStyle.copyWith(color: fg),
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
        child: InkWell(onTap: widget.onTap, borderRadius: radius, child: child),
      ),
    );
  }
}

/// Attached run controls: one rectangle, equal-width segments, hairline splits.
///
/// Segments are sized to the widest label so Run / Run Project / Stop line up
/// instead of each hugging its own text.
class ToolbarButtonGroup extends StatelessWidget {
  const ToolbarButtonGroup({
    super.key,
    required this.buttons,
    this.height = AppControlHeight.toolbarAction,
  });

  final List<ToolbarButton> buttons;
  final double height;

  /// Widest segment content, so every segment can adopt it.
  static double segmentWidth(List<ToolbarButton> buttons, double textScale) {
    var widest = 0.0;
    for (final button in buttons) {
      var width = ToolbarButton.iconSize + ToolbarButton.labelPadding * 2;
      if (button.showLabel) {
        final painter = TextPainter(
          text: TextSpan(
            text: button.label.toUpperCase(),
            style: ToolbarButton.labelStyle,
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(textScale),
        )..layout();
        width += ToolbarButton.iconLabelGap + painter.width;
      }
      widest = width > widest ? width : widest;
    }
    return widest.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (buttons.isEmpty) return const SizedBox.shrink();
    final width = segmentWidth(
      buttons,
      MediaQuery.textScalerOf(context).scale(1),
    );
    // The shared 1px outline is drawn outside the segments, so they fill what
    // is left of [height] — otherwise the bar would measure height + 2.
    final segmentHeight = height - 2;

    final children = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: segmentHeight,
            color: context.palette.border,
          ),
        );
      }
      final button = buttons[i];
      children.add(
        ToolbarButton(
          key: button.key,
          icon: button.icon,
          label: button.label,
          onTap: button.onTap,
          primary: button.primary,
          danger: button.danger,
          showLabel: button.showLabel,
          tooltip: button.tooltip,
          position: buttons.length == 1
              ? ToolbarButtonPosition.standalone
              : i == 0
              ? ToolbarButtonPosition.first
              : i == buttons.length - 1
              ? ToolbarButtonPosition.last
              : ToolbarButtonPosition.middle,
          width: width,
          height: segmentHeight,
        ),
      );
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
