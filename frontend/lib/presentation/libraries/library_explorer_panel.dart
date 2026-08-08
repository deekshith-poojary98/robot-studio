import 'package:flutter/material.dart';

import '../../core/gateway/models/library_info.dart';
import '../../core/theme/app_theme.dart';
import '../editor/editor_syntax.dart';
import '../widgets/empty_state.dart';
import '../widgets/robot_documentation.dart';
import '../widgets/skeleton_list.dart';
import 'library_explorer_controller.dart';

/// Side-rail Library Explorer — presentation only; filtering lives in the controller.
class LibraryExplorerPanel extends StatefulWidget {
  const LibraryExplorerPanel({
    super.key,
    required this.hasProject,
    required this.controller,
    required this.onJumpToSource,
  });

  final bool hasProject;
  final LibraryExplorerController controller;
  final void Function(String path, int? line) onJumpToSource;

  @override
  State<LibraryExplorerPanel> createState() => _LibraryExplorerPanelState();
}

class _LibraryExplorerPanelState extends State<LibraryExplorerPanel> {
  final TextEditingController _filterController = TextEditingController();

  LibraryExplorerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.hasProject) {
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant LibraryExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasProject && !oldWidget.hasProject) {
      _reload();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await _c.loadLibraries();
    if (mounted) setState(() {});
  }

  Future<void> _openLibrary(LibraryInfo lib) async {
    await _c.openLibrary(lib);
    if (mounted) setState(() {});
  }

  void _back() {
    _c.back();
    if (_c.level == LibraryExplorerLevel.libraries) {
      _filterController.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasProject) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No project open',
        message: 'Open a project to browse Robot Framework libraries.',
        compact: true,
      );
    }

    if (_c.loading && _c.libraries.isEmpty) {
      return const SkeletonList(rows: 8);
    }

    if (_c.error != null && _c.libraries.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load libraries',
        message: _c.error!,
        actionLabel: 'Retry',
        onAction: _reload,
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.level != LibraryExplorerLevel.libraries)
          _BackBar(
            label: _c.level == LibraryExplorerLevel.detail
                ? (_c.selectedKeyword?.name ?? 'Keyword')
                : (_c.selectedLibrary?.name ?? 'Library'),
            onBack: _back,
          ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    return switch (_c.level) {
      LibraryExplorerLevel.libraries => _LibraryList(
        libraries: _c.libraries,
        onOpen: _openLibrary,
      ),
      LibraryExplorerLevel.keywords => _KeywordList(
        library: _c.selectedLibrary,
        filterController: _filterController,
        keywords: _c.filteredKeywords,
        loading: _c.loadingDetail,
        onFilterChanged: (value) {
          _c.setKeywordFilter(value);
          setState(() {});
        },
        onOpen: (kw) {
          _c.openKeyword(kw);
          setState(() {});
        },
      ),
      LibraryExplorerLevel.detail => _KeywordDetail(
        keyword: _c.selectedKeyword!,
        libraryName: _c.selectedLibrary?.name ?? '',
        onJump: _c.selectedKeyword!.canJumpToSource
            ? () => widget.onJumpToSource(
                _c.selectedKeyword!.sourcePath,
                _c.selectedKeyword!.sourceLine,
              )
            : null,
      ),
    };
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onBack,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.arrow_back,
              size: 16,
              color: context.palette.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.libraries, required this.onOpen});

  final List<LibraryInfo> libraries;
  final ValueChanged<LibraryInfo> onOpen;

  @override
  Widget build(BuildContext context) {
    if (libraries.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No libraries',
        message: 'BuiltIn and imported libraries will appear here.',
        compact: true,
      );
    }
    return ListView.builder(
      itemCount: libraries.length,
      itemBuilder: (context, index) {
        final lib = libraries[index];
        final countLabel = lib.keywordCount > 0
            ? '${lib.keywordCount} keywords'
            : 'Imported · tap to load';
        return ListTile(
          dense: true,
          title: Text(
            lib.name,
            style: TextStyle(fontSize: 13, color: context.palette.textPrimary),
          ),
          subtitle: Text(
            [if (lib.builtin) 'BuiltIn', countLabel].join(' · '),
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
          onTap: () => onOpen(lib),
        );
      },
    );
  }
}

class _KeywordList extends StatelessWidget {
  const _KeywordList({
    required this.library,
    required this.filterController,
    required this.keywords,
    required this.loading,
    required this.onFilterChanged,
    required this.onOpen,
  });

  final LibraryInfo? library;
  final TextEditingController filterController;
  final List<LibraryKeywordInfo> keywords;
  final bool loading;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<LibraryKeywordInfo> onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading && (library?.keywords.isEmpty ?? true)) {
      return const SkeletonList(rows: 10);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: filterController,
            onChanged: onFilterChanged,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search keywords…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
        ),
        Expanded(
          child: keywords.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'No keywords',
                  message: 'Try a different search, or open another library.',
                  compact: true,
                )
              : ListView.builder(
                  itemCount: keywords.length,
                  itemBuilder: (context, index) {
                    final kw = keywords[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        kw.name,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.textPrimary,
                        ),
                      ),
                      onTap: () => onOpen(kw),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _KeywordDetail extends StatelessWidget {
  const _KeywordDetail({
    required this.keyword,
    required this.libraryName,
    this.onJump,
  });

  final LibraryKeywordInfo keyword;
  final String libraryName;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          keyword.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Documentation',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        RobotDocumentation(
          documentation: keyword.documentation,
          format: RobotDocFormat.fromLibdoc(keyword.docFormat),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Arguments',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (keyword.parameters.isEmpty)
          Text(
            'None',
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          )
        else
          for (final param in keyword.parameters)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: SelectableText.rich(
                highlightKeywordArgument(
                  param.displayLabel,
                  context.palette,
                  base: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: param.required
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Defined in',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          keyword.libraryName.isNotEmpty ? keyword.libraryName : libraryName,
          style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
        ),
        if (onJump != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onJump,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Jump to source'),
            ),
          ),
        ],
      ],
    );
  }
}
