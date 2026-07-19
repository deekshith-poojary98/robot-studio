import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'index_status_card.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({
    super.key,
    required this.query,
    required this.kind,
    required this.results,
    required this.isSearching,
    required this.indexStatus,
    required this.isLoadingStatus,
    this.selected,
    this.hover,
    this.references = const [],
    this.isLoadingLanguage = false,
    this.navigationMessage,
    required this.onQueryChanged,
    required this.onKindChanged,
    required this.onSearch,
    required this.onSelect,
    required this.onGoToDefinition,
    required this.onFindReferences,
    required this.onShowHover,
    required this.onRebuildIndex,
    this.onOpenPlaceholder,
  });

  final String query;
  final SymbolKind? kind;
  final List<IndexedSymbolInfo> results;
  final bool isSearching;
  final IndexStatusInfo? indexStatus;
  final bool isLoadingStatus;
  final IndexedSymbolInfo? selected;
  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final bool isLoadingLanguage;
  final String? navigationMessage;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SymbolKind?> onKindChanged;
  final VoidCallback onSearch;
  final ValueChanged<IndexedSymbolInfo> onSelect;
  final VoidCallback onGoToDefinition;
  final VoidCallback onFindReferences;
  final VoidCallback onShowHover;
  final VoidCallback onRebuildIndex;
  final VoidCallback? onOpenPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Search indexed keywords, variables, libraries, resources, and files.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: IndexStatusCard(
              status: indexStatus,
              isLoading: isLoadingStatus,
              onRebuild: onRebuildIndex,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search symbols…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: onQueryChanged,
                    onSubmitted: (_) => onSearch(),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<SymbolKind?>(
                  value: kind,
                  hint: const Text('All kinds'),
                  items: [
                    const DropdownMenuItem<SymbolKind?>(
                      value: null,
                      child: Text('All'),
                    ),
                    ...SymbolKind.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: onKindChanged,
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: onSearch,
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _ResultsList(
                    results: results,
                    isSearching: isSearching,
                    selectedId: selected?.id,
                    onSelect: onSelect,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: _DetailPane(
                    selected: selected,
                    hover: hover,
                    references: references,
                    isLoadingLanguage: isLoadingLanguage,
                    navigationMessage: navigationMessage,
                    onGoToDefinition: onGoToDefinition,
                    onFindReferences: onFindReferences,
                    onShowHover: onShowHover,
                    onOpenPlaceholder: onOpenPlaceholder,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.isSearching,
    required this.selectedId,
    required this.onSelect,
  });

  final List<IndexedSymbolInfo> results;
  final bool isSearching;
  final String? selectedId;
  final ValueChanged<IndexedSymbolInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No symbols found. Rebuild the index or refine your query.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = results[index];
        final selected = item.id == selectedId;
        return Material(
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () => onSelect(item),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      StatusBadge(label: item.kind.label),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.selected,
    required this.hover,
    required this.references,
    required this.isLoadingLanguage,
    required this.navigationMessage,
    required this.onGoToDefinition,
    required this.onFindReferences,
    required this.onShowHover,
    this.onOpenPlaceholder,
  });

  final IndexedSymbolInfo? selected;
  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final bool isLoadingLanguage;
  final String? navigationMessage;
  final VoidCallback onGoToDefinition;
  final VoidCallback onFindReferences;
  final VoidCallback onShowHover;
  final VoidCallback? onOpenPlaceholder;

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return Center(
        child: Text(
          'Select a symbol to inspect definition, hover, and references.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final item = selected!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        StatusBadge(label: item.kind.label, filled: true),
        const SizedBox(height: 10),
        Text(item.locationLabel, style: Theme.of(context).textTheme.bodySmall),
        if (item.detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.detail, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (item.documentation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(item.documentation),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: onGoToDefinition,
              child: const Text('Go to Definition'),
            ),
            OutlinedButton(
              onPressed: onFindReferences,
              child: const Text('Find References'),
            ),
            OutlinedButton(
              onPressed: onShowHover,
              child: const Text('Hover Info'),
            ),
            if (onOpenPlaceholder != null)
              TextButton(
                onPressed: onOpenPlaceholder,
                child: const Text('Open File (placeholder)'),
              ),
          ],
        ),
        if (navigationMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(navigationMessage!),
          ),
        ],
        if (isLoadingLanguage) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        if (hover != null) ...[
          const SizedBox(height: 16),
          Text('Hover', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${hover!.kind.label} · ${hover!.filePath}:${hover!.line}'),
          if (hover!.documentation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(hover!.documentation),
          ],
        ],
        if (references.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('References', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...references.map(
            (ref) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ref.filePath}:${ref.line}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  if (ref.context.isNotEmpty)
                    Text(
                      ref.context,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
