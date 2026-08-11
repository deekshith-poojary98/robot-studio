import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../editor/editor_syntax.dart';

/// Matches [RobotCodeEditor] defaults so Diff reads like the open editor.
const _kDiffFontFamily = 'Menlo';
const _kDiffFontSize = 13.0;
const _kDiffTabWidth = 4;
const _kDiffLineHeight = 18.0;
const _kDiffGutterWidth = 36.0;

class DiffViewer extends StatelessWidget {
  const DiffViewer({
    super.key,
    required this.diff,
    required this.isLoading,
    this.fileLabel,
  });

  final GitDiffInfo? diff;
  final bool isLoading;
  final String? fileLabel;

  @override
  Widget build(BuildContext context) {
    final path = fileLabel ?? diff?.filePath;
    final hasFile = path != null && path.isNotEmpty;
    final showDiff = !isLoading && diff != null && diff!.lines.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFile) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              path,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ),
          Divider(height: 1, color: context.palette.borderSubtle),
        ],
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : showDiff
              ? _SideBySideDiff(lines: diff!.lines, filePath: path)
              : Center(
                  child: Text(
                    'Select a changed file to view diff',
                    style: TextStyle(color: context.palette.textMuted),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SideBySideDiff extends StatefulWidget {
  const _SideBySideDiff({required this.lines, this.filePath});

  final List<GitDiffLineInfo> lines;
  final String? filePath;

  @override
  State<_SideBySideDiff> createState() => _SideBySideDiffState();
}

class _SideBySideDiffState extends State<_SideBySideDiff> {
  final _leftVertical = ScrollController();
  final _rightVertical = ScrollController();
  final _leftHorizontal = ScrollController();
  final _rightHorizontal = ScrollController();
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _leftVertical.addListener(_syncFromLeft);
    _rightVertical.addListener(_syncFromRight);
  }

  @override
  void dispose() {
    _leftVertical
      ..removeListener(_syncFromLeft)
      ..dispose();
    _rightVertical
      ..removeListener(_syncFromRight)
      ..dispose();
    _leftHorizontal.dispose();
    _rightHorizontal.dispose();
    super.dispose();
  }

  void _syncFromLeft() => _syncVertical(_leftVertical, _rightVertical);

  void _syncFromRight() => _syncVertical(_rightVertical, _leftVertical);

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < 0.5) return;
    _syncingVertical = true;
    target.jumpTo(offset);
    _syncingVertical = false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = TextStyle(
      color: palette.textPrimary,
      fontSize: _kDiffFontSize,
      fontFamily: _kDiffFontFamily,
      height: 1.0,
      letterSpacing: 0,
      wordSpacing: 0,
    );
    final path = widget.filePath ?? '';
    final leftTexts = widget.lines
        .map((line) => _expandTabs(line.left))
        .toList(growable: false);
    final rightTexts = widget.lines
        .map((line) => _expandTabs(line.right))
        .toList(growable: false);
    final leftSpans = highlightLinesForPath(
      leftTexts,
      path,
      palette,
      base: base,
    );
    final rightSpans = highlightLinesForPath(
      rightTexts,
      path,
      palette,
      base: base,
    );
    final leftContentWidth = _maxLineWidth(leftSpans);
    final rightContentWidth = _maxLineWidth(rightSpans);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _DiffColumn(
            side: _DiffSide.left,
            lines: widget.lines,
            lineSpans: leftSpans,
            baseStyle: base,
            contentWidth: leftContentWidth,
            verticalController: _leftVertical,
            horizontalController: _leftHorizontal,
          ),
        ),
        VerticalDivider(width: 1, color: context.palette.borderSubtle),
        Expanded(
          child: _DiffColumn(
            side: _DiffSide.right,
            lines: widget.lines,
            lineSpans: rightSpans,
            baseStyle: base,
            contentWidth: rightContentWidth,
            verticalController: _rightVertical,
            horizontalController: _rightHorizontal,
          ),
        ),
      ],
    );
  }
}

enum _DiffSide { left, right }

class _DiffColumn extends StatelessWidget {
  const _DiffColumn({
    required this.side,
    required this.lines,
    required this.lineSpans,
    required this.baseStyle,
    required this.contentWidth,
    required this.verticalController,
    required this.horizontalController,
  });

  final _DiffSide side;
  final List<GitDiffLineInfo> lines;
  final List<TextSpan> lineSpans;
  final TextStyle baseStyle;
  final double contentWidth;
  final ScrollController verticalController;
  final ScrollController horizontalController;

  @override
  Widget build(BuildContext context) {
    final gutterStyle = baseStyle.copyWith(
      color: context.palette.textMuted,
      fontSize: 11,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = math.max(
          constraints.maxWidth,
          _kDiffGutterWidth + contentWidth + AppSpacing.sm,
        );

        return Scrollbar(
          controller: horizontalController,
          thumbVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: paneWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: verticalController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: verticalController,
                  padding: EdgeInsets.zero,
                  itemExtent: _kDiffLineHeight,
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    final text = side == _DiffSide.left
                        ? line.left
                        : line.right;
                    final lineNumber = side == _DiffSide.left
                        ? line.leftLine
                        : line.rightLine;
                    final background = _backgroundFor(
                      context.palette,
                      line.kind,
                      side,
                    );

                    if (text.isEmpty && lineNumber == null) {
                      return const SizedBox(height: _kDiffLineHeight);
                    }

                    final span = index < lineSpans.length
                        ? lineSpans[index]
                        : TextSpan(
                            text: _expandTabs(text.isEmpty ? ' ' : text),
                            style: baseStyle,
                          );

                    return ColoredBox(
                      color: background,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _kDiffGutterWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.xs,
                              ),
                              child: Text(
                                lineNumber?.toString() ?? '',
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                style: gutterStyle,
                              ),
                            ),
                          ),
                          DefaultTextStyle(
                            style: baseStyle,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            child: Text.rich(
                              _ensureVisibleSpan(span, baseStyle),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: baseStyle,
                              strutStyle: const StrutStyle(
                                fontFamily: _kDiffFontFamily,
                                fontSize: _kDiffFontSize,
                                height: 1.0,
                                forceStrutHeight: true,
                                leading: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _backgroundFor(AppPalette palette, String kind, _DiffSide side) {
    // A wash of the semantic colour, so the tint reads on either brightness
    // instead of being a fixed dark overlay.
    const alpha = 0.13;
    return switch (kind) {
      'added' when side == _DiffSide.right => palette.success.withValues(
        alpha: alpha,
      ),
      'removed' when side == _DiffSide.left => palette.error.withValues(
        alpha: alpha,
      ),
      'modified' => palette.warning.withValues(alpha: alpha),
      _ => Colors.transparent,
    };
  }
}

double _maxLineWidth(List<TextSpan> spans) {
  var maxWidth = 0.0;
  for (final span in spans) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (painter.width > maxWidth) {
      maxWidth = painter.width;
    }
  }
  return maxWidth;
}

TextSpan _ensureVisibleSpan(TextSpan span, TextStyle base) {
  final empty =
      (span.text == null || span.text!.isEmpty) &&
      (span.children == null || span.children!.isEmpty);
  if (empty) {
    return TextSpan(text: ' ', style: base);
  }
  return span;
}

/// Expand tabs the same way the editor does ([RobotCodeEditor.tabWidth] = 4).
String _expandTabs(String input, {int tabWidth = _kDiffTabWidth}) {
  if (!input.contains('\t')) return input;
  final buffer = StringBuffer();
  var column = 0;
  for (final unit in input.codeUnits) {
    if (unit == 0x09) {
      final spaces = tabWidth - (column % tabWidth);
      buffer.write(' ' * spaces);
      column += spaces;
    } else {
      buffer.writeCharCode(unit);
      column += 1;
    }
  }
  return buffer.toString();
}
