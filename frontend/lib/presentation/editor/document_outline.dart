import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Document symbols for the active editor file (nested DocumentSymbolTree).
///
/// Use [embedded] for the VS Code-style pane under Explorer.
class DocumentOutlinePanel extends StatelessWidget {
  const DocumentOutlinePanel({
    super.key,
    required this.isLoading,
    this.root,
    this.filePath = '',
    this.symbols = const [],
    this.onSelect,
    this.selectedId,
    this.embedded = false,
    this.initiallyExpanded = false,
  });

  /// Preferred: live analysis root from DocumentAnalysisService.
  final DocumentSymbolNode? root;
  final String filePath;

  /// Legacy flat list when analysis is unavailable.
  final List<IndexedSymbolInfo> symbols;
  final bool isLoading;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool embedded;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return _EmbeddedOutline(
        root: root,
        filePath: filePath,
        symbols: symbols,
        isLoading: isLoading,
        onSelect: onSelect,
        selectedId: selectedId,
        initiallyExpanded: initiallyExpanded,
      );
    }

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Text(
              'Outline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _OutlineBody(
              root: root,
              filePath: filePath,
              symbols: symbols,
              isLoading: isLoading,
              onSelect: onSelect,
              selectedId: selectedId,
              compact: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedOutline extends StatefulWidget {
  const _EmbeddedOutline({
    required this.isLoading,
    this.root,
    this.filePath = '',
    this.symbols = const [],
    this.onSelect,
    this.selectedId,
    this.initiallyExpanded = false,
  });

  final DocumentSymbolNode? root;
  final String filePath;
  final List<IndexedSymbolInfo> symbols;
  final bool isLoading;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool initiallyExpanded;

  @override
  State<_EmbeddedOutline> createState() => _EmbeddedOutlineState();
}

class _EmbeddedOutlineState extends State<_EmbeddedOutline> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'OUTLINE',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          SizedBox(
            height: 220,
            child: _OutlineBody(
              root: widget.root,
              filePath: widget.filePath,
              symbols: widget.symbols,
              isLoading: widget.isLoading,
              onSelect: widget.onSelect,
              selectedId: widget.selectedId,
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _OutlineBody extends StatefulWidget {
  const _OutlineBody({
    required this.isLoading,
    required this.compact,
    this.root,
    this.filePath = '',
    this.symbols = const [],
    this.onSelect,
    this.selectedId,
  });

  final DocumentSymbolNode? root;
  final String filePath;
  final List<IndexedSymbolInfo> symbols;
  final bool isLoading;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool compact;

  @override
  State<_OutlineBody> createState() => _OutlineBodyState();
}

class _OutlineBodyState extends State<_OutlineBody> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final root = widget.root;
    final hasTree = root != null && root.name.isNotEmpty;
    final hasFlat = widget.symbols.isNotEmpty;
    if (!hasTree && !hasFlat) {
      return EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No symbols',
        message: widget.compact
            ? 'Open a file to see its outline.'
            : 'No symbols in this file.',
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 8 : 12,
            4,
            widget.compact ? 8 : 12,
            4,
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter outline…',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, size: 14),
              prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child: hasTree
              ? _TreeOutline(
                  root: _filterNode(root, _query) ?? root,
                  filePath: widget.filePath,
                  onSelect: widget.onSelect,
                  selectedId: widget.selectedId,
                  compact: widget.compact,
                  depth: 0,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _filteredFlat().length,
                  itemBuilder: (context, index) {
                    final symbol = _filteredFlat()[index];
                    return _FlatRow(
                      symbol: symbol,
                      selected: symbol.id == widget.selectedId,
                      compact: widget.compact,
                      onTap: widget.onSelect == null
                          ? null
                          : () => widget.onSelect!(symbol),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<IndexedSymbolInfo> _filteredFlat() {
    final needle = _query.toLowerCase();
    if (needle.isEmpty) return widget.symbols;
    return widget.symbols
        .where((s) => s.name.toLowerCase().contains(needle))
        .toList();
  }

  DocumentSymbolNode? _filterNode(DocumentSymbolNode node, String query) {
    final needle = query.toLowerCase();
    if (needle.isEmpty) return node;
    final kept = <DocumentSymbolNode>[];
    for (final child in node.children) {
      final filtered = _filterNode(child, query);
      if (filtered != null) kept.add(filtered);
    }
    final selfMatch = node.name.toLowerCase().contains(needle) ||
        node.detail.toLowerCase().contains(needle);
    if (!selfMatch && kept.isEmpty) return null;
    return DocumentSymbolNode(
      id: node.id,
      name: node.name,
      kind: node.kind,
      line: node.line,
      endLine: node.endLine,
      column: node.column,
      detail: node.detail,
      documentation: node.documentation,
      children: kept,
    );
  }
}

class _TreeOutline extends StatelessWidget {
  const _TreeOutline({
    required this.root,
    required this.filePath,
    required this.compact,
    required this.depth,
    this.onSelect,
    this.selectedId,
  });

  final DocumentSymbolNode root;
  final String filePath;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool compact;
  final int depth;

  @override
  Widget build(BuildContext context) {
    // Show suite children (sections) at top level; skip duplicate root chrome.
    final nodes = depth == 0 &&
            (root.kind == SymbolKind.testSuite || root.kind == SymbolKind.resource)
        ? root.children
        : [root];

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final node in nodes)
            _TreeNode(
              node: node,
              filePath: filePath,
              onSelect: onSelect,
              selectedId: selectedId,
              compact: compact,
              depth: depth == 0 ? 0 : depth,
            ),
      ],
    );
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.node,
    required this.filePath,
    required this.compact,
    required this.depth,
    this.onSelect,
    this.selectedId,
  });

  final DocumentSymbolNode node;
  final String filePath;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool compact;
  final int depth;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  late bool _expanded = widget.node.kind == SymbolKind.section;

  @override
  void didUpdateWidget(covariant _TreeNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId &&
        widget.selectedId != null &&
        _containsId(widget.node, widget.selectedId!)) {
      _expanded = true;
    }
  }

  bool _containsId(DocumentSymbolNode node, String id) {
    if (node.id == id) return true;
    return node.children.any((c) => _containsId(c, id));
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final selected = node.id == widget.selectedId;
    final hasKids = node.hasChildren;
    // Nested calls / control under tests start collapsed.
    final showKids = hasKids && _expanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (hasKids) {
              setState(() => _expanded = !_expanded);
            }
            widget.onSelect?.call(node.toIndexed(widget.filePath));
          },
          child: Container(
            padding: EdgeInsets.only(
              left: (widget.compact ? 12 : 8) + widget.depth * 12.0,
              right: 8,
              top: widget.compact ? 3 : 5,
              bottom: widget.compact ? 3 : 5,
            ),
            color: selected ? AppColors.accentSoft : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: hasKids
                      ? Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 14,
                          color: AppColors.textMuted,
                        )
                      : const SizedBox.shrink(),
                ),
                Icon(
                  _iconForKind(node.kind),
                  size: 13,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showKids)
          for (final child in node.children)
            _TreeNode(
              node: child,
              filePath: widget.filePath,
              onSelect: widget.onSelect,
              selectedId: widget.selectedId,
              compact: widget.compact,
              depth: widget.depth + 1,
            ),
      ],
    );
  }

  IconData _iconForKind(SymbolKind kind) {
    return switch (kind) {
      SymbolKind.keyword => Icons.vpn_key_outlined,
      SymbolKind.variable => Icons.data_object,
      SymbolKind.testCase => Icons.science_outlined,
      SymbolKind.testSuite => Icons.description_outlined,
      SymbolKind.library => Icons.library_books_outlined,
      SymbolKind.resource => Icons.link,
      SymbolKind.setting => Icons.settings_outlined,
      SymbolKind.tag => Icons.sell_outlined,
      SymbolKind.section => Icons.folder_outlined,
      SymbolKind.keywordCall => Icons.play_arrow_outlined,
      SymbolKind.control => Icons.code,
      _ => Icons.circle_outlined,
    };
  }
}

class _FlatRow extends StatelessWidget {
  const _FlatRow({
    required this.symbol,
    required this.selected,
    required this.compact,
    this.onTap,
  });

  final IndexedSymbolInfo symbol;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: compact ? 20 : 12,
          right: 8,
          top: compact ? 3 : 6,
          bottom: compact ? 3 : 6,
        ),
        color: selected ? AppColors.accentSoft : Colors.transparent,
        child: Row(
          children: [
            Icon(
              Icons.circle_outlined,
              size: 14,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                symbol.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  color: selected ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
