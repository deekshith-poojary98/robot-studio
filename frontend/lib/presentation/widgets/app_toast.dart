import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppToastCorner { topRight, bottomRight }

OverlayEntry? _activeToast;

/// Dark floating toast that slides in from a corner (not a full-width banner).
void showAppToast(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
  AppToastCorner corner = AppToastCorner.bottomRight,
  IconData icon = Icons.info_outline,
  Color? iconColor,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeToast?.remove();
  _activeToast = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AppToastCard(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      corner: corner,
      icon: icon,
      iconColor: iconColor ?? context.palette.info,
      onDismiss: () {
        entry.remove();
        if (identical(_activeToast, entry)) {
          _activeToast = null;
        }
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _AppToastCard extends StatefulWidget {
  const _AppToastCard({
    required this.message,
    required this.duration,
    required this.corner,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final AppToastCorner corner;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;

  @override
  State<_AppToastCard> createState() => _AppToastCardState();
}

class _AppToastCardState extends State<_AppToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.18, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    if (widget.actionLabel == null) {
      _autoClose = Timer(widget.duration, () => unawaited(_dismiss()));
    } else {
      _autoClose = Timer(widget.duration, () => unawaited(_dismiss()));
    }
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _autoClose?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.corner == AppToastCorner.topRight;
    final maxWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
      240.0,
      380.0,
    );

    return Positioned(
      right: 16,
      top: top ? 16 : null,
      bottom: top ? null : 56,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: context.palette.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: 16, color: widget.iconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null &&
                          widget.onAction != null) ...[
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () {
                            widget.onAction!();
                            unawaited(_dismiss());
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: context.palette.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => unawaited(_dismiss()),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        iconSize: 16,
                        color: context.palette.textMuted,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
