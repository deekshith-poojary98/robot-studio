import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            fileLabel ?? diff?.filePath ?? 'Diff',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : diff == null || diff!.lines.isEmpty
              ? Center(
                  child: Text(
                    'Select a changed file to view diff',
                    style: TextStyle(color: context.palette.textMuted),
                  ),
                )
              : _SideBySideDiff(lines: diff!.lines),
        ),
      ],
    );
  }
}

class _SideBySideDiff extends StatelessWidget {
  const _SideBySideDiff({required this.lines});

  final List<GitDiffLineInfo> lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _DiffColumn(side: _DiffSide.left, lines: lines),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _DiffColumn(side: _DiffSide.right, lines: lines),
        ),
      ],
    );
  }
}

enum _DiffSide { left, right }

class _DiffColumn extends StatelessWidget {
  const _DiffColumn({required this.side, required this.lines});

  final _DiffSide side;
  final List<GitDiffLineInfo> lines;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final text = side == _DiffSide.left ? line.left : line.right;
        final lineNumber = side == _DiffSide.left
            ? line.leftLine
            : line.rightLine;
        final background = _backgroundFor(context.palette, line.kind, side);
        final foreground = _foregroundFor(context.palette, line.kind);

        if (text.isEmpty && lineNumber == null) {
          return const SizedBox(height: 20);
        }

        return ColoredBox(
          color: background,
          child: SizedBox(
            height: 20,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    lineNumber?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: context.palette.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text.isEmpty ? ' ' : text,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
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

  Color _foregroundFor(AppPalette palette, String kind) {
    return switch (kind) {
      'added' => palette.success,
      'removed' => palette.error,
      'modified' => palette.warning,
      _ => palette.textPrimary,
    };
  }
}
