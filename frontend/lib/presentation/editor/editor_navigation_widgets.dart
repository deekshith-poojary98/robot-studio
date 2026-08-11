import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

class EditorBreadcrumbBar extends StatelessWidget {
  const EditorBreadcrumbBar({
    super.key,
    required this.breadcrumb,
    this.onSegmentTap,
  });

  final EditorBreadcrumbInfo breadcrumb;
  final ValueChanged<BreadcrumbSegment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final segments = breadcrumb.segments.isNotEmpty
        ? breadcrumb.segments
        : _legacySegments(breadcrumb);

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: context.palette.textMuted,
                ),
              ),
            _BreadcrumbChip(
              segment: segments[i],
              isLast: i == segments.length - 1,
              onTap: onSegmentTap == null
                  ? null
                  : () => onSegmentTap!(segments[i]),
            ),
          ],
        ],
      ),
    );
  }

  List<BreadcrumbSegment> _legacySegments(EditorBreadcrumbInfo info) {
    final out = <BreadcrumbSegment>[];
    if (info.workspace != null && info.workspace!.isNotEmpty) {
      out.add(BreadcrumbSegment(label: info.workspace!));
    }
    if (info.project != null && info.project!.isNotEmpty) {
      out.add(BreadcrumbSegment(label: info.project!));
    }
    if (info.folder != null && info.folder!.isNotEmpty) {
      out.add(BreadcrumbSegment(label: info.folder!));
    }
    if (info.fileName != null && info.fileName!.isNotEmpty) {
      out.add(BreadcrumbSegment(label: info.fileName!));
    }
    if (info.symbol != null) {
      out.add(
        BreadcrumbSegment(
          label: info.symbol!.name,
          path: info.symbol!.filePath,
          line: info.symbol!.line,
        ),
      );
    }
    return out;
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.segment,
    required this.isLast,
    this.onTap,
  });

  final BreadcrumbSegment segment;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final navigable =
        onTap != null && (segment.path != null || segment.line != null);
    final style = TextStyle(
      fontSize: 11,
      color: isLast ? context.palette.textPrimary : context.palette.textMuted,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );

    if (!navigable) {
      return Text(segment.label, style: style);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(segment.label, style: style),
      ),
    );
  }
}

class SignatureHelpOverlay extends StatelessWidget {
  const SignatureHelpOverlay({super.key, required this.signature});

  final SignatureHelpInfo signature;

  @override
  Widget build(BuildContext context) {
    return EditorHoverTooltip(signature: signature);
  }
}

/// Result of [computeHoverTooltipPlacement].
class HoverTooltipPlacement {
  const HoverTooltipPlacement({required this.left, required this.top});

  final double left;
  final double top;
}

/// Prefer below the line; flip above when the card would not fit.
///
/// [anchor] may be the caret, a pointer in the glyphs, or line-top.
/// The occupied line is snapped from that point so the card never covers
/// the arguments. Vertical overflow is allowed (the editor stack does not
/// clip) instead of sliding the card onto the line to stay in-viewport.
HoverTooltipPlacement computeHoverTooltipPlacement({
  required Offset anchor,
  required Size viewport,
  required Size tooltipSize,
  double lineHeight = 20,
  double gap = 8,
  double margin = 8,
  double offsetX = 12,
}) {
  final width = tooltipSize.width
      .clamp(EditorHoverTooltip.minWidth, EditorHoverTooltip.maxWidth)
      .toDouble();
  final height = tooltipSize.height
      .clamp(48.0, EditorHoverTooltip.maxHeight)
      .toDouble();

  final safeLineHeight = lineHeight <= 0 ? 20.0 : lineHeight;
  final lineTop = (anchor.dy / safeLineHeight).floor() * safeLineHeight;
  final lineBottom = lineTop + safeLineHeight;

  final belowTop = lineBottom + gap;
  final aboveTop = lineTop - gap - height;
  final spaceBelow = viewport.height - belowTop - margin;
  final spaceAbove = lineTop - gap - margin;
  final preferAbove = spaceBelow < height && spaceAbove > spaceBelow;

  final top = preferAbove ? aboveTop : belowTop;

  var left = anchor.dx + offsetX;
  final maxLeft = math.max(margin, viewport.width - width - margin);
  if (left + width > viewport.width - margin) {
    left = viewport.width - width - margin;
  }
  left = left.clamp(margin, maxLeft).toDouble();

  return HoverTooltipPlacement(left: left, top: top);
}

/// VS Code-style hover / signature card shown near the pointer.
class EditorHoverTooltip extends StatelessWidget {
  const EditorHoverTooltip({super.key, required this.signature});

  final SignatureHelpInfo signature;

  static const double maxWidth = 620;
  static const double minWidth = 200;
  static const double maxHeight = 280;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxWidth,
          minWidth: minWidth,
          maxHeight: maxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.palette.borderSubtle),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  signature.keyword,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.palette.textPrimary,
                  ),
                ),
                if (signature.libraryName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    signature.libraryName,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
                if (signature.parameters.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < signature.parameters.length; i++)
                        _ParameterChip(
                          parameter: signature.parameters[i],
                          active: i == signature.activeParameter,
                        ),
                    ],
                  ),
                ] else if (signature.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    signature.detail,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
                if (signature.documentation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    signature.documentation,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParameterChip extends StatelessWidget {
  const _ParameterChip({required this.parameter, required this.active});

  final SignatureParameterInfo parameter;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = parameter.displayLabel;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? context.palette.accentSoft : context.palette.rail,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? context.palette.accent : context.palette.borderSubtle,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: parameter.required || active
              ? FontWeight.w600
              : FontWeight.w400,
          color: active
              ? context.palette.textPrimary
              : context.palette.textSecondary,
        ),
      ),
    );
    if (parameter.documentation.isEmpty) return chip;
    return Tooltip(
      message: parameter.documentation,
      waitDuration: const Duration(milliseconds: 250),
      child: chip,
    );
  }
}

class PeekDefinitionPanel extends StatelessWidget {
  const PeekDefinitionPanel({
    super.key,
    required this.symbol,
    required this.onOpen,
    required onClose,
  }) : _onClose = onClose;

  final IndexedSymbolInfo symbol;
  final VoidCallback onOpen;
  final VoidCallback _onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(left: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.palette.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Peek Definition',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  tooltip: 'Open',
                  onPressed: onOpen,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('${symbol.kind.label}: ${symbol.name}'),
                Text(
                  symbol.locationLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (symbol.documentation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(symbol.documentation),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
