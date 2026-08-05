import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Tooltip that **always** honors [waitDuration], even when moving between
/// siblings.
///
/// Material [Tooltip] skips the wait when another tooltip was just open
/// (`Tooltip._openedTooltips` → `withDelay: Duration.zero`). That feels right
/// for toolbar icons, but for Explorer path tips it makes the second hover
/// flash the full path instantly.
class AlwaysDelayedTooltip extends StatefulWidget {
  const AlwaysDelayedTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 700),
  });

  final String message;
  final Widget child;
  final Duration waitDuration;

  @override
  State<AlwaysDelayedTooltip> createState() => _AlwaysDelayedTooltipState();
}

class _AlwaysDelayedTooltipState extends State<AlwaysDelayedTooltip> {
  final LayerLink _link = LayerLink();
  Timer? _timer;
  OverlayEntry? _entry;

  @override
  void dispose() {
    _timer?.cancel();
    _removeEntry();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AlwaysDelayedTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message && _entry != null) {
      _entry!.markNeedsBuild();
    }
  }

  void _onEnter(PointerEnterEvent _) {
    _timer?.cancel();
    _timer = Timer(widget.waitDuration, _show);
  }

  void _onExit(PointerExitEvent _) {
    _timer?.cancel();
    _timer = null;
    _removeEntry();
  }

  void _show() {
    if (!mounted || _entry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _buildTip);
    overlay.insert(_entry!);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildTip(BuildContext context) {
    final theme = Theme.of(context);
    return UnconstrainedBox(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(8, 6),
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            color: context.palette.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  widget.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.palette.textPrimary,
                    fontFamily: 'Menlo',
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      tooltip: widget.message,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: _onEnter,
          onExit: _onExit,
          child: widget.child,
        ),
      ),
    );
  }
}
