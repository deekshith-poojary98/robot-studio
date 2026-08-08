import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Vertical drag strip between the side panel and the editor.
class SidePanelResizeHandle extends StatefulWidget {
  const SidePanelResizeHandle({super.key, required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  State<SidePanelResizeHandle> createState() => _SidePanelResizeHandleState();
}

class _SidePanelResizeHandleState extends State<SidePanelResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) {
          widget.onDragDelta(details.delta.dx);
        },
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: ColoredBox(
          color: context.palette.surface,
          child: SizedBox(
            width: 5,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: active ? 2 : 1,
                color: active
                    ? context.palette.accent
                    : context.palette.borderSubtle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
