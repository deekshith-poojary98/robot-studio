import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Renders Robot Framework/libdoc documentation without dropping its structure.
///
/// Robot docs are not Markdown. Their common format is `= Heading =`,
/// paragraphs, `- bullets`, inline `*bold*` / `_italic_` / `` `code` ``, and
/// pipe-formatted tables/examples. This renderer intentionally stays small and
/// lossless: unrecognised content is still emitted verbatim.
class RobotDocumentation extends StatelessWidget {
  const RobotDocumentation({
    super.key,
    required this.documentation,
    this.emptyMessage = 'No documentation available.',
  });

  final String documentation;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final normalized = documentation
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) {
      return SelectableText(
        emptyMessage,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: context.palette.textMuted,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final blocks = _parseBlocks(normalized);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _DocumentationBlock(block: blocks[i]),
        ],
      ],
    );
  }
}

enum _BlockKind { paragraph, heading, bullet, ordered, code }

class _DocBlock {
  const _DocBlock(this.kind, this.text, {this.level = 1, this.prefix = ''});

  final _BlockKind kind;
  final String text;
  final int level;
  final String prefix;
}

List<_DocBlock> _parseBlocks(String documentation) {
  final lines = documentation.split('\n');
  final blocks = <_DocBlock>[];
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      index++;
      continue;
    }

    final heading = RegExp(r'^(={1,5})\s*(.*?)\s*\1$').firstMatch(trimmed);
    if (heading != null && heading.group(2)!.isNotEmpty) {
      blocks.add(
        _DocBlock(
          _BlockKind.heading,
          heading.group(2)!,
          level: heading.group(1)!.length,
        ),
      );
      index++;
      continue;
    }

    final bullet = RegExp(r'^\s*[-*]\s+(.+)$').firstMatch(line);
    if (bullet != null) {
      blocks.add(_DocBlock(_BlockKind.bullet, bullet.group(1)!));
      index++;
      continue;
    }

    final ordered = RegExp(r'^\s*(\d+[.)])\s+(.+)$').firstMatch(line);
    if (ordered != null) {
      blocks.add(
        _DocBlock(
          _BlockKind.ordered,
          ordered.group(2)!,
          prefix: ordered.group(1)!,
        ),
      );
      index++;
      continue;
    }

    if (_isCodeLine(line)) {
      final code = <String>[];
      while (index < lines.length &&
          (lines[index].trim().isEmpty || _isCodeLine(lines[index]))) {
        code.add(lines[index]);
        index++;
      }
      while (code.isNotEmpty && code.last.trim().isEmpty) {
        code.removeLast();
      }
      blocks.add(_DocBlock(_BlockKind.code, code.join('\n')));
      continue;
    }

    final paragraph = <String>[trimmed];
    index++;
    while (index < lines.length) {
      final next = lines[index];
      final nextTrimmed = next.trim();
      if (nextTrimmed.isEmpty ||
          RegExp(r'^(={1,5})\s*(.*?)\s*\1$').hasMatch(nextTrimmed) ||
          RegExp(r'^\s*[-*]\s+(.+)$').hasMatch(next) ||
          RegExp(r'^\s*(\d+[.)])\s+(.+)$').hasMatch(next) ||
          _isCodeLine(next)) {
        break;
      }
      paragraph.add(nextTrimmed);
      index++;
    }
    blocks.add(_DocBlock(_BlockKind.paragraph, paragraph.join('\n')));
  }
  return blocks;
}

bool _isCodeLine(String line) {
  final left = line.trimLeft();
  return left.startsWith('|') ||
      line.startsWith('    ') ||
      line.startsWith('\t');
}

class _DocumentationBlock extends StatelessWidget {
  const _DocumentationBlock({required this.block});

  final _DocBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block.kind) {
      _BlockKind.heading => SelectableText.rich(
        TextSpan(
          children: _inlineSpans(context, block.text),
          style: TextStyle(
            fontSize: block.level == 1 ? 13 : 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: context.palette.textPrimary,
          ),
        ),
        key: const Key('robot-doc-heading'),
      ),
      _BlockKind.bullet || _BlockKind.ordered => Row(
        key: Key(
          block.kind == _BlockKind.bullet
              ? 'robot-doc-bullet'
              : 'robot-doc-ordered',
        ),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: block.kind == _BlockKind.bullet ? 16 : 24,
            child: Text(
              block.kind == _BlockKind.bullet ? '•' : block.prefix,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.palette.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                children: _inlineSpans(context, block.text),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.palette.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      _BlockKind.code => Container(
        key: const Key('robot-doc-code'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.palette.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.xs),
          border: Border.all(color: context.palette.borderSubtle),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            block.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.45,
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ),
      _BlockKind.paragraph => SelectableText.rich(
        TextSpan(
          children: _inlineSpans(context, block.text),
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: context.palette.textSecondary,
          ),
        ),
      ),
    };
  }
}

List<InlineSpan> _inlineSpans(BuildContext context, String text) {
  final spans = <InlineSpan>[];
  final token = RegExp(r'(\*[^*\n]+\*|_[^_\n]+_|`[^`\n]+`|[$@&%]\{[^}\n]+\})');
  var cursor = 0;

  for (final match in token.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final raw = match.group(0)!;
    if (raw.startsWith('*')) {
      spans.add(
        TextSpan(
          text: raw.substring(1, raw.length - 1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (raw.startsWith('_')) {
      spans.add(
        TextSpan(
          text: raw.substring(1, raw.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: raw.startsWith('`') ? raw.substring(1, raw.length - 1) : raw,
          style: TextStyle(
            fontFamily: 'monospace',
            color: context.palette.textPrimary,
            backgroundColor: context.palette.surfaceElevated,
          ),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}
