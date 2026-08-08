import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../editor/editor_syntax.dart';

/// Documentation dialects a library docstring can be written in.
///
/// Robot Framework libraries declare this via `ROBOT_LIBRARY_DOC_FORMAT`, which
/// libdoc surfaces as `doc_format`. Older libraries use Robot's own markup;
/// newer ones increasingly ship Markdown.
enum RobotDocFormat {
  /// Sniff the text — explicit Markdown markers win, otherwise Robot.
  auto,

  /// Robot Framework markup: `= Heading =`, `| ` preformatted, ``` ``code``` ```.
  robot,

  /// CommonMark-ish Markdown: `#` headings, fences, `**bold**`, `[l](url)`.
  markdown,

  /// Plain text, shown verbatim.
  text,

  /// HTML, normalised to Robot markup before rendering.
  html;

  /// Maps libdoc's `doc_format` string onto a dialect.
  ///
  /// `ROBOT` is libdoc's default, so a library that writes Markdown without
  /// declaring a format also arrives as `ROBOT` — those fall through to
  /// [RobotDocFormat.auto] so the text itself decides.
  static RobotDocFormat fromLibdoc(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'MARKDOWN':
      case 'MD':
        return RobotDocFormat.markdown;
      case 'HTML':
        return RobotDocFormat.html;
      // reST is not rendered as rich text, but its source reads fine verbatim.
      case 'TEXT':
      case 'REST':
      case 'RST':
        return RobotDocFormat.text;
      default:
        return RobotDocFormat.auto;
    }
  }
}

/// Renders library documentation without dropping its structure.
///
/// Supports both dialects found in the wild: Robot Framework markup (matching
/// libdoc's own formatter rules) and Markdown. Unrecognised content is always
/// emitted verbatim rather than silently swallowed.
class RobotDocumentation extends StatelessWidget {
  const RobotDocumentation({
    super.key,
    required this.documentation,
    this.format = RobotDocFormat.auto,
    this.emptyMessage = 'No documentation available.',
  });

  final String documentation;

  /// Declared dialect. Defaults to sniffing the text.
  final RobotDocFormat format;
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

    final source = format == RobotDocFormat.html
        ? htmlToRobotMarkup(normalized)
        : normalized;
    final blocks = switch (resolveDocFormat(format, source)) {
      RobotDocFormat.markdown => _parseMarkdownBlocks(source),
      RobotDocFormat.text => [_DocBlock(_BlockKind.code, source)],
      _ => _parseRobotBlocks(source),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].kind.gapBefore),
          _DocumentationBlock(block: blocks[i]),
        ],
      ],
    );
  }
}

/// Resolves a declared format against the text, sniffing when unknown.
@visibleForTesting
RobotDocFormat resolveDocFormat(RobotDocFormat declared, String text) {
  return switch (declared) {
    RobotDocFormat.auto =>
      looksLikeMarkdown(text) ? RobotDocFormat.markdown : RobotDocFormat.robot,
    // HTML is converted to Robot markup by the parser, so it renders as Robot.
    RobotDocFormat.html => RobotDocFormat.robot,
    _ => declared,
  };
}

/// True when the text carries markers that only Markdown uses.
///
/// Scored rather than first-match so a stray character cannot flip a whole
/// Robot docstring into the wrong dialect.
@visibleForTesting
bool looksLikeMarkdown(String text) {
  var markdown = 0;
  var robot = 0;

  bool has(String pattern) => RegExp(pattern, multiLine: true).hasMatch(text);

  // Markdown-only structures.
  if (has(r'^ {0,3}```')) markdown += 3;
  if (has(r'^ {0,3}~~~')) markdown += 3;
  if (has(r'^ {0,3}#{1,6} +\S')) markdown += 3;
  if (has(r'\*\*[^\s*][^*]*\*\*')) markdown += 2;
  if (has(r'\[[^\]\n]+\]\([^)\s]+\)')) markdown += 2;
  if (has(r'~~[^\s~][^~]*~~')) markdown += 1;
  if (has(r'^ {0,3}> ')) markdown += 1;
  if (has(r'^ {0,3}\d+[.)] +\S')) markdown += 1;
  if (has(r'^ {0,3}[*+] +\S')) markdown += 1;
  // Robot tables never carry a '|---|' row, so this alone settles the dialect.
  if (text.split('\n').any(isMarkdownTableDelimiter)) markdown += 3;

  // Robot-only structures.
  if (has(r'^ {0,3}={1,3} +\S.*\S +={1,3}\s*$')) robot += 3;
  if (has(r'``[^\s`][^`]*``')) robot += 3;
  if (has(r'^ {0,3}\| ')) robot += 2;
  if (text.contains('%TOC%')) robot += 3;

  return markdown > robot;
}

/// True for a Markdown table delimiter row such as `|---|:--:|`.
@visibleForTesting
bool isMarkdownTableDelimiter(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('|') || !trimmed.contains('-')) return false;
  return trimmed.replaceAll(RegExp(r'[|\-:\s]'), '').isEmpty;
}

/// Rewrites the small HTML subset libdoc emits into Robot markup.
///
/// Mirrors `robot.libdocpkg.htmlutils.HtmlToText`: this is a normaliser, not an
/// HTML engine, so unknown tags are dropped and their text is kept.
@visibleForTesting
String htmlToRobotMarkup(String html) {
  var text = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true), '')
      .replaceAll(RegExp(r'<h([1-6])[^>]*>', caseSensitive: false), '\n= ')
      .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), ' =\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ')
      .replaceAll(RegExp(r'<(br|hr) */?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</?(p|div|ul|ol|tr|table)[^>]*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'</?(b|strong)[^>]*>', caseSensitive: false), '*')
      .replaceAll(RegExp(r'</?(i|em)[^>]*>', caseSensitive: false), '_')
      .replaceAll(RegExp(r'</?(code|tt)[^>]*>', caseSensitive: false), '``')
      .replaceAll(RegExp(r'<pre[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</pre>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '');
  for (final entity in const {
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&nbsp;': ' ',
    '&amp;': '&',
  }.entries) {
    text = text.replaceAll(entity.key, entity.value);
  }
  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

enum _BlockKind {
  paragraph,
  heading,
  bullet,
  ordered,
  code,
  quote,
  rule,
  table;

  double get gapBefore => switch (this) {
    _BlockKind.bullet || _BlockKind.ordered => AppSpacing.xs,
    _BlockKind.heading => AppSpacing.md,
    _ => AppSpacing.sm,
  };
}

class _DocBlock {
  const _DocBlock(
    this.kind,
    this.text, {
    this.level = 1,
    this.prefix = '',
    this.markdown = false,
    this.robotSyntax = false,
    this.rows = const [],
    this.hasHeaderRow = false,
  });

  final _BlockKind kind;
  final String text;
  final int level;
  final String prefix;

  /// Which inline dialect applies to [text].
  final bool markdown;

  /// When [kind] is code, paint with the editor's Robot grammar.
  final bool robotSyntax;

  /// Cells for [_BlockKind.table].
  final List<List<String>> rows;
  final bool hasHeaderRow;
}

// --------------------------------------------------------------------------
// Robot Framework markup
// --------------------------------------------------------------------------

final _robotHeading = RegExp(r'^(={1,3}) +(\S.*?) +\1$');
final _robotRule = RegExp(r'^-{3,}$');
final _robotTableRow = RegExp(r'^\| (.* |)\|$');

bool _isRobotPreformatted(String line) =>
    line.startsWith('| ') || line.trimRight() == '|';

/// RF section headers accept 3+ asterisks; library docs often pad them
/// (``***** Settings *****``) so they are not eaten by bold ``*text*`` markup.
/// Examples should show the canonical ``*** Settings ***`` form.
final _robotSectionHeader = RegExp(
  r'^(\s*)\*{3,}\s+(\S(?:.*\S)?)\s+\*{3,}\s*$',
);

String _normalizeRobotExampleLine(String line) {
  final match = _robotSectionHeader.firstMatch(line);
  if (match == null) return line;
  return '${match.group(1)}*** ${match.group(2)} ***';
}

/// Canonicalises padded RF section headers in example blocks.
@visibleForTesting
String normalizeRobotExampleLine(String line) =>
    _normalizeRobotExampleLine(line);

/// True when a Markdown fence/indent looks like Robot Framework source.
bool _looksLikeRobotExample(String code) {
  return RegExp(
        r'^\*{3}\s*(Settings?|Variables?|Test Cases?|Tasks?|Keywords?)',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(code) ||
      RegExp(
        r'^(Library|Resource|Variables)\b',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(code);
}

/// Parses Robot Framework markup, following libdoc's own formatter precedence:
/// table, preformatted, list, heading, ruler, then paragraph.
List<_DocBlock> _parseRobotBlocks(String documentation) {
  final lines = documentation.split('\n');
  final blocks = <_DocBlock>[];
  var index = 0;

  bool startsBlock(String line) {
    final trimmed = line.trim();
    return trimmed.isEmpty ||
        _robotTableRow.hasMatch(trimmed) ||
        _isRobotPreformatted(line) ||
        trimmed.startsWith('- ') ||
        _robotHeading.hasMatch(trimmed) ||
        _robotRule.hasMatch(trimmed);
  }

  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      index++;
      continue;
    }

    // Tables need a closing pipe; without one the line is preformatted.
    if (_robotTableRow.hasMatch(trimmed)) {
      final rows = <List<String>>[];
      var headerRow = false;
      while (index < lines.length &&
          _robotTableRow.hasMatch(lines[index].trim())) {
        final cells = _splitRobotRow(lines[index].trim());
        if (rows.isEmpty && cells.every(_isRobotHeaderCell)) headerRow = true;
        rows.add(cells.map(_stripRobotHeaderCell).toList());
        index++;
      }
      blocks.add(
        _DocBlock(_BlockKind.table, '', rows: rows, hasHeaderRow: headerRow),
      );
      continue;
    }

    if (_isRobotPreformatted(line)) {
      final code = <String>[];
      while (index < lines.length && _isRobotPreformatted(lines[index])) {
        // libdoc drops the leading '| ' marker from preformatted lines.
        final raw = lines[index];
        final body = raw.startsWith('| ') ? raw.substring(2) : '';
        code.add(_normalizeRobotExampleLine(body));
        index++;
      }
      while (code.isNotEmpty && code.last.trim().isEmpty) {
        code.removeLast();
      }
      blocks.add(
        _DocBlock(_BlockKind.code, code.join('\n'), robotSyntax: true),
      );
      continue;
    }

    // Robot lists use '- ' only; continuation lines are indented.
    if (trimmed.startsWith('- ')) {
      final item = <String>[trimmed.substring(2).trim()];
      index++;
      while (index < lines.length) {
        final next = lines[index];
        if (next.trim().isEmpty ||
            next.trim().startsWith('- ') ||
            !next.startsWith(' ')) {
          break;
        }
        item.add(next.trim());
        index++;
      }
      blocks.add(_DocBlock(_BlockKind.bullet, item.join(' ')));
      continue;
    }

    final heading = _robotHeading.firstMatch(trimmed);
    if (heading != null) {
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

    if (_robotRule.hasMatch(trimmed)) {
      blocks.add(const _DocBlock(_BlockKind.rule, ''));
      index++;
      continue;
    }

    // Paragraph: libdoc joins its lines with a space and lets them wrap.
    final paragraph = <String>[trimmed];
    index++;
    while (index < lines.length && !startsBlock(lines[index])) {
      paragraph.add(lines[index].trim());
      index++;
    }
    blocks.add(_DocBlock(_BlockKind.paragraph, paragraph.join(' ')));
  }
  return blocks;
}

List<String> _splitRobotRow(String line) {
  final inner = line.substring(1, line.length - 1);
  return inner.split(RegExp(r' \|(?= )')).map((cell) => cell.trim()).toList();
}

bool _isRobotHeaderCell(String cell) =>
    cell.length > 1 && cell.startsWith('=') && cell.endsWith('=');

String _stripRobotHeaderCell(String cell) =>
    _isRobotHeaderCell(cell) ? cell.substring(1, cell.length - 1).trim() : cell;

// --------------------------------------------------------------------------
// Markdown
// --------------------------------------------------------------------------

final _mdHeading = RegExp(r'^ {0,3}(#{1,6}) +(.*?)\s*#*\s*$');
final _mdFence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*(\S*)');
final _mdRule = RegExp(r'^ {0,3}([-*_])(?: *\1){2,} *$');
final _mdBullet = RegExp(r'^ {0,3}[-*+] +(.*)$');
final _mdOrdered = RegExp(r'^ {0,3}(\d+)[.)] +(.*)$');
final _mdQuote = RegExp(r'^ {0,3}> ?(.*)$');
final _mdSetext = RegExp(r'^ {0,3}(=+|-+) *$');

/// Parses Markdown into the same block model used for Robot markup.
List<_DocBlock> _parseMarkdownBlocks(String documentation) {
  final lines = documentation.split('\n');
  final blocks = <_DocBlock>[];
  var index = 0;

  bool startsBlock(String line) {
    final trimmed = line.trim();
    return trimmed.isEmpty ||
        _mdHeading.hasMatch(line) ||
        _mdFence.hasMatch(line) ||
        _mdRule.hasMatch(line) ||
        _mdBullet.hasMatch(line) ||
        _mdOrdered.hasMatch(line) ||
        _mdQuote.hasMatch(line) ||
        line.startsWith('    ') ||
        line.startsWith('\t');
  }

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    final fence = _mdFence.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)![0];
      final closer = RegExp('^ {0,3}[$marker]{${fence.group(1)!.length},} *\$');
      index++;
      final code = <String>[];
      while (index < lines.length && !closer.hasMatch(lines[index])) {
        code.add(lines[index]);
        index++;
      }
      // Skip the closing fence when present; an unclosed fence just ends.
      if (index < lines.length) index++;
      final body = code.join('\n');
      blocks.add(
        _DocBlock(
          _BlockKind.code,
          body,
          markdown: true,
          robotSyntax: _looksLikeRobotExample(body),
        ),
      );
      continue;
    }

    final heading = _mdHeading.firstMatch(line);
    if (heading != null) {
      blocks.add(
        _DocBlock(
          _BlockKind.heading,
          heading.group(2)!.trim(),
          level: heading.group(1)!.length,
          markdown: true,
        ),
      );
      index++;
      continue;
    }

    // Rule check precedes tables/lists so '---' is not read as a bullet.
    if (_mdRule.hasMatch(line)) {
      blocks.add(const _DocBlock(_BlockKind.rule, ''));
      index++;
      continue;
    }

    // A pipe row followed by a delimiter row is a table.
    if (line.contains('|') &&
        index + 1 < lines.length &&
        isMarkdownTableDelimiter(lines[index + 1])) {
      final rows = <List<String>>[_splitMarkdownRow(line)];
      index += 2;
      while (index < lines.length &&
          lines[index].contains('|') &&
          lines[index].trim().isNotEmpty) {
        rows.add(_splitMarkdownRow(lines[index]));
        index++;
      }
      blocks.add(
        _DocBlock(
          _BlockKind.table,
          '',
          rows: rows,
          hasHeaderRow: true,
          markdown: true,
        ),
      );
      continue;
    }

    final quote = _mdQuote.firstMatch(line);
    if (quote != null) {
      final body = <String>[quote.group(1)!.trim()];
      index++;
      while (index < lines.length) {
        final next = _mdQuote.firstMatch(lines[index]);
        if (next == null) break;
        body.add(next.group(1)!.trim());
        index++;
      }
      blocks.add(
        _DocBlock(_BlockKind.quote, body.join(' ').trim(), markdown: true),
      );
      continue;
    }

    final ordered = _mdOrdered.firstMatch(line);
    final bullet = ordered == null ? _mdBullet.firstMatch(line) : null;
    if (ordered != null || bullet != null) {
      final item = _collectListItem(
        lines,
        index,
        (ordered?.group(2) ?? bullet!.group(1))!,
      );
      blocks.add(
        _DocBlock(
          ordered != null ? _BlockKind.ordered : _BlockKind.bullet,
          item.text,
          prefix: ordered != null ? '${ordered.group(1)!}.' : '',
          markdown: true,
        ),
      );
      index = item.nextIndex;
      continue;
    }

    if (line.startsWith('    ') || line.startsWith('\t')) {
      final code = <String>[];
      while (index < lines.length &&
          (lines[index].trim().isEmpty ||
              lines[index].startsWith('    ') ||
              lines[index].startsWith('\t'))) {
        code.add(_stripIndent(lines[index]));
        index++;
      }
      while (code.isNotEmpty && code.last.trim().isEmpty) {
        code.removeLast();
      }
      final body = code.join('\n');
      blocks.add(
        _DocBlock(
          _BlockKind.code,
          body,
          markdown: true,
          robotSyntax: _looksLikeRobotExample(body),
        ),
      );
      continue;
    }

    final paragraph = <String>[line.trim()];
    index++;
    while (index < lines.length && !startsBlock(lines[index])) {
      // A '===' / '---' underline turns the paragraph into a setext heading.
      if (paragraph.length == 1 && _mdSetext.hasMatch(lines[index])) {
        blocks.add(
          _DocBlock(
            _BlockKind.heading,
            paragraph.first,
            level: lines[index].trim().startsWith('=') ? 1 : 2,
            markdown: true,
          ),
        );
        index++;
        paragraph.clear();
        break;
      }
      paragraph.add(lines[index].trim());
      index++;
    }
    if (paragraph.isNotEmpty) {
      blocks.add(
        _DocBlock(_BlockKind.paragraph, paragraph.join(' '), markdown: true),
      );
    }
  }
  return blocks;
}

/// Consumes a list item plus its lazy-continuation lines.
({String text, int nextIndex}) _collectListItem(
  List<String> lines,
  int start,
  String first,
) {
  final item = <String>[first.trim()];
  var index = start + 1;
  while (index < lines.length) {
    final next = lines[index];
    if (next.trim().isEmpty ||
        _mdBullet.hasMatch(next) ||
        _mdOrdered.hasMatch(next) ||
        _mdHeading.hasMatch(next) ||
        _mdFence.hasMatch(next) ||
        _mdQuote.hasMatch(next)) {
      break;
    }
    item.add(next.trim());
    index++;
  }
  return (text: item.join(' '), nextIndex: index);
}

List<String> _splitMarkdownRow(String line) {
  var row = line.trim();
  if (row.startsWith('|')) row = row.substring(1);
  if (row.endsWith('|') && !row.endsWith(r'\|')) {
    row = row.substring(0, row.length - 1);
  }
  return row
      .split(RegExp(r'(?<!\\)\|'))
      .map((cell) => cell.replaceAll(r'\|', '|').trim())
      .toList();
}

String _stripIndent(String line) {
  if (line.startsWith('    ')) return line.substring(4);
  if (line.startsWith('\t')) return line.substring(1);
  return line.trimLeft();
}

// --------------------------------------------------------------------------
// Rendering
// --------------------------------------------------------------------------

class _DocumentationBlock extends StatelessWidget {
  const _DocumentationBlock({required this.block});

  final _DocBlock block;

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: context.palette.textSecondary,
    );

    return switch (block.kind) {
      _BlockKind.heading => SelectableText.rich(
        TextSpan(
          children: _inlineSpans(context, block.text, markdown: block.markdown),
          style: TextStyle(
            fontSize: switch (block.level) {
              1 => 13.5,
              2 => 12.5,
              _ => 12,
            },
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
            width: block.kind == _BlockKind.bullet ? 16 : 26,
            child: Text(
              block.kind == _BlockKind.bullet ? '•' : block.prefix,
              // A wide marker ('10.') must overflow the gutter, not wrap.
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: body.copyWith(color: context.palette.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                children: _inlineSpans(
                  context,
                  block.text,
                  markdown: block.markdown,
                ),
                style: body,
              ),
            ),
          ),
        ],
      ),
      _BlockKind.quote => Container(
        key: const Key('robot-doc-quote'),
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: context.palette.border, width: 2),
          ),
        ),
        child: SelectableText.rich(
          TextSpan(
            children: _inlineSpans(
              context,
              block.text,
              markdown: block.markdown,
            ),
            style: body.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ),
      _BlockKind.rule => Divider(
        key: const Key('robot-doc-rule'),
        height: AppSpacing.md,
        color: context.palette.borderSubtle,
      ),
      _BlockKind.table => _DocTable(block: block),
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
          child: block.robotSyntax
              ? SelectableText.rich(
                  highlightRobotSource(
                    block.text,
                    context.palette,
                    base: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.45,
                      color: context.palette.textPrimary,
                    ),
                  ),
                )
              : SelectableText(
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
          children: _inlineSpans(context, block.text, markdown: block.markdown),
          style: body,
        ),
        key: const Key('robot-doc-paragraph'),
      ),
    };
  }
}

class _DocTable extends StatelessWidget {
  const _DocTable({required this.block});

  final _DocBlock block;

  @override
  Widget build(BuildContext context) {
    final columns = block.rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    if (columns == 0) return const SizedBox.shrink();

    return Container(
      key: const Key('robot-doc-table'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder.symmetric(
          inside: BorderSide(color: context.palette.borderSubtle),
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          for (var r = 0; r < block.rows.length; r++)
            TableRow(
              decoration: r == 0 && block.hasHeaderRow
                  ? BoxDecoration(color: context.palette.surfaceElevated)
                  : null,
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: SelectableText.rich(
                      TextSpan(
                        children: _inlineSpans(
                          context,
                          c < block.rows[r].length ? block.rows[r][c] : '',
                          markdown: block.markdown,
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: r == 0 && block.hasHeaderRow
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: r == 0 && block.hasHeaderRow
                              ? context.palette.textPrimary
                              : context.palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Inline markup
// --------------------------------------------------------------------------

/// Robot inline markup, mirroring `robot.utils.htmlformatters.LineFormatter`.
///
/// Each marker must open at a word boundary and close before whitespace or
/// closing punctuation, which is what keeps `a * b * c` from turning bold.
/// Double backticks are code; a single backtick is a keyword/section link.
final _robotInline = RegExp(
  r'''(?<![^\s"'(_])\*(?![\s*])([^*\n]*?)\*(?=["').,!?:;_]*(?:\s|$))'''
  r'''|(?<![^\s"'(])_(?![\s_])([^_\n]*?)_(?=["').,!?:;]*(?:\s|$))'''
  r'''|(?<![^\s"'(])``(?!\s)(.+?)``(?=["').,!?:;]*(?:\s|$))'''
  r'''|`([^`\n]+?)`'''
  r'''|(https?://[^\s<>"']+)'''
  r'''|([$@&%]\{[^}\n]*\})''',
);

/// Markdown inline markup. Code spans win so backticked markers stay literal.
final _markdownInline = RegExp(
  r'(`+)([^`]|[^`].*?[^`])\1(?!`)'
  r'|\!?\[([^\]\n]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)'
  r'|\*\*(?=\S)(.+?)(?<=\S)\*\*'
  r'|__(?=\S)(.+?)(?<=\S)__'
  r'|~~(?=\S)(.+?)(?<=\S)~~'
  r'|\*(?=\S)([^*\n]+?)(?<=\S)\*'
  r'|(?<![A-Za-z0-9_])_(?=\S)([^_\n]+?)(?<=\S)_(?![A-Za-z0-9_])'
  r'|<(https?://[^>\s]+)>'
  r'|(https?://[^\s<>]+)',
);

List<InlineSpan> _inlineSpans(
  BuildContext context,
  String text, {
  required bool markdown,
}) {
  if (text.isEmpty) return const [];
  final spans = <InlineSpan>[];
  final pattern = markdown ? _markdownInline : _robotInline;
  var cursor = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start < cursor) continue;
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(
      markdown ? _markdownSpan(context, match) : _robotSpan(context, match),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

InlineSpan _robotSpan(BuildContext context, RegExpMatch match) {
  final bold = match.group(1);
  if (bold != null) {
    return TextSpan(
      children: _inlineSpans(context, bold, markdown: false),
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
  final italic = match.group(2);
  if (italic != null) {
    return TextSpan(
      children: _inlineSpans(context, italic, markdown: false),
      style: const TextStyle(fontStyle: FontStyle.italic),
    );
  }
  final code = match.group(3);
  if (code != null) return _codeSpan(context, code);

  // Single backticks are libdoc's link syntax, not code.
  final link = match.group(4);
  if (link != null) {
    return TextSpan(
      text: link,
      style: TextStyle(
        color: context.palette.accent,
        fontWeight: FontWeight.w500,
      ),
    );
  }
  final url = match.group(5);
  if (url != null) return _linkSpan(context, url);

  return _codeSpan(context, match.group(6)!);
}

InlineSpan _markdownSpan(BuildContext context, RegExpMatch match) {
  final code = match.group(2);
  if (code != null) return _codeSpan(context, code.trim());

  final linkText = match.group(3);
  if (linkText != null) {
    final target = match.group(4) ?? '';
    return _linkSpan(context, linkText.isEmpty ? target : linkText);
  }
  final strong = match.group(5) ?? match.group(6);
  if (strong != null) {
    return TextSpan(
      children: _inlineSpans(context, strong, markdown: true),
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
  final struck = match.group(7);
  if (struck != null) {
    return TextSpan(
      children: _inlineSpans(context, struck, markdown: true),
      style: const TextStyle(decoration: TextDecoration.lineThrough),
    );
  }
  final emphasis = match.group(8) ?? match.group(9);
  if (emphasis != null) {
    return TextSpan(
      children: _inlineSpans(context, emphasis, markdown: true),
      style: const TextStyle(fontStyle: FontStyle.italic),
    );
  }
  return _linkSpan(context, match.group(10) ?? match.group(11)!);
}

TextSpan _codeSpan(BuildContext context, String text) => TextSpan(
  text: text,
  style: TextStyle(
    fontFamily: 'monospace',
    color: context.palette.textPrimary,
    backgroundColor: context.palette.surfaceElevated,
  ),
);

TextSpan _linkSpan(BuildContext context, String text) => TextSpan(
  text: text,
  style: TextStyle(
    color: context.palette.accent,
    decoration: TextDecoration.underline,
    decorationColor: context.palette.accent,
  ),
);
