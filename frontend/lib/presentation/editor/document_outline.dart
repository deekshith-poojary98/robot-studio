import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/theme/app_theme.dart';

class DocumentOutlinePanel extends StatelessWidget {
  const DocumentOutlinePanel({
    super.key,
    required this.symbols,
    required this.isLoading,
    this.onSelect,
  });

  final List<IndexedSymbolInfo> symbols;
  final bool isLoading;
  final ValueChanged<IndexedSymbolInfo>? onSelect;

  @override
  Widget build(BuildContext context) {
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
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : symbols.isEmpty
                    ? Center(
                        child: Text(
                          'No symbols in this file.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        itemCount: symbols.length,
                        itemBuilder: (context, index) {
                          final symbol = symbols[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              symbol.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            subtitle: Text(
                              '${symbol.kind.label} · L${symbol.line}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: onSelect == null
                                ? null
                                : () => onSelect!(symbol),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
