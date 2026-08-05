import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/models/content_search_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';

/// Side-rail Find in Files — plain-text content search (not symbol search).
class FindInFilesPanel extends StatefulWidget {
  const FindInFilesPanel({
    super.key,
    required this.hasProject,
    required this.onSearch,
    required this.onOpenMatch,
    this.onOpenSymbols,
  });

  final bool hasProject;
  final Future<ContentSearchResultInfo> Function(String query) onSearch;
  final void Function(String path, int line, int column) onOpenMatch;
  final VoidCallback? onOpenSymbols;

  @override
  State<FindInFilesPanel> createState() => _FindInFilesPanelState();
}

class _FindInFilesPanelState extends State<FindInFilesPanel> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _searching = false;
  ContentSearchResultInfo? _result;
  String? _error;
  final Set<String> _expanded = {};
  bool _expansionSeeded = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
        _searching = false;
        _expanded.clear();
        _expansionSeeded = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_runSearch(trimmed));
    });
  }

  Future<void> _runSearch(String query) async {
    final gen = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await widget.onSearch(query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _result = result;
        _searching = false;
        if (!_expansionSeeded) {
          _expanded.clear();
          if (result.files.length == 1) {
            _expanded.add(result.files.first.path);
          }
          _expansionSeeded = true;
        } else {
          // Keep remembered expansion; auto-expand new single-file results.
          if (result.files.length == 1) {
            _expanded.add(result.files.first.path);
          }
        }
      });
    } catch (error) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _searching = false;
        _error = error.toString();
        _result = null;
      });
    }
  }

  void _toggle(String path) {
    setState(() {
      if (_expanded.contains(path)) {
        _expanded.remove(path);
      } else {
        _expanded.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasProject) {
      return const EmptyState(
        icon: Icons.search_off_outlined,
        title: 'No project open',
        message: 'Open a project to search file contents.',
        compact: true,
      );
    }

    final result = _result;
    final rows = <_Row>[];
    if (result != null) {
      for (final file in result.files) {
        final expanded = _expanded.contains(file.path);
        rows.add(_Row.file(file, expanded));
        if (expanded) {
          for (final match in file.matches) {
            rows.add(_Row.match(file.path, match));
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search in files…',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
            ),
            onChanged: _onQueryChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) unawaited(_runSearch(trimmed));
            },
          ),
        ),
        if (widget.onOpenSymbols != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onOpenSymbols,
                child: const Text('Symbols…'),
              ),
            ),
          ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        if (result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              result.truncated
                  ? '${result.totalMatches}+ matches in ${result.files.length} files'
                        ' (truncated · ${result.filesScanned} scanned)'
                  : '${result.totalMatches} matches in ${result.files.length} files'
                        ' (${result.filesScanned} scanned)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _buildBody(rows)),
      ],
    );
  }

  Widget _buildBody(List<_Row> rows) {
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Search failed',
        message: _error!,
        compact: true,
      );
    }
    if (_searching && (_result == null || _result!.files.isEmpty)) {
      return const SkeletonList(rows: 6);
    }
    if (_controller.text.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.find_in_page_outlined,
        title: 'Find in Files',
        message: 'Type to search raw file contents across the project.',
        compact: true,
      );
    }
    if (rows.isEmpty && !_searching) {
      return const EmptyState(
        icon: Icons.search_off_outlined,
        title: 'No matches',
        message: 'Try a different query.',
        compact: true,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isFile) {
          final file = row.file!;
          final expanded = row.expanded;
          return InkWell(
            onTap: () => _toggle(file.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: context.palette.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: context.palette.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${file.matchCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }
        final match = row.match!;
        final enclosing = match.enclosing;
        return InkWell(
          onTap: () => widget.onOpenMatch(row.path!, match.line, match.column),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (enclosing != null)
                  Text(
                    '${enclosing.kind} · ${enclosing.name}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: context.palette.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  'L${match.line}:${match.column}  ${match.text.trim()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Menlo',
                    color: context.palette.textPrimary,
                  ),
                ),
                if (match.before.isNotEmpty || match.after.isNotEmpty)
                  Text(
                    [
                      ...match.before.map((line) => '  $line'),
                      ...match.after.map((line) => '  $line'),
                    ].join('\n'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Menlo',
                      color: context.palette.textSecondary.withValues(
                        alpha: 0.9,
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
}

class _Row {
  const _Row.file(this.file, this.expanded)
    : path = null,
      match = null,
      isFile = true;

  const _Row.match(this.path, this.match)
    : file = null,
      expanded = false,
      isFile = false;

  final bool isFile;
  final ContentFileHitsInfo? file;
  final bool expanded;
  final String? path;
  final ContentMatchInfo? match;
}
