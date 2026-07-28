import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Document symbols for the active editor file.
///
/// Use [embedded] for the VS Code-style pane under Explorer (collapsible
/// section, fills remaining height). Without [embedded], renders as a fixed
/// 240px side column (legacy editor layout).
class DocumentOutlinePanel extends StatelessWidget {
  const DocumentOutlinePanel({
    super.key,
    required this.symbols,
    required this.isLoading,
    this.onSelect,
    this.selectedId,
    this.embedded = false,
    this.initiallyExpanded = true,
  });

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
          Expanded(child: _OutlineBody(
            symbols: symbols,
            isLoading: isLoading,
            onSelect: onSelect,
            selectedId: selectedId,
            compact: false,
          )),
        ],
      ),
    );
  }
}

class _EmbeddedOutline extends StatefulWidget {
  const _EmbeddedOutline({
    required this.symbols,
    required this.isLoading,
    this.onSelect,
    this.selectedId,
    this.initiallyExpanded = true,
  });

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
            height: 180,
            child: _OutlineBody(
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

class _OutlineBody extends StatelessWidget {
  const _OutlineBody({
    required this.symbols,
    required this.isLoading,
    this.onSelect,
    this.selectedId,
    required this.compact,
  });

  final List<IndexedSymbolInfo> symbols;
  final bool isLoading;
  final ValueChanged<IndexedSymbolInfo>? onSelect;
  final String? selectedId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (symbols.isEmpty) {
      return EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No symbols',
        message: compact
            ? 'Open a file to see its outline.'
            : 'No symbols in this file.',
        compact: true,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: symbols.length,
      itemBuilder: (context, index) {
        final symbol = symbols[index];
        final selected = symbol.id == selectedId;
        return InkWell(
          onTap: onSelect == null ? null : () => onSelect!(symbol),
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
                  _iconForKind(symbol.kind),
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
                      color: selected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (!compact)
                  Text(
                    'L${symbol.line}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
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
      _ => Icons.circle_outlined,
    };
  }
}
