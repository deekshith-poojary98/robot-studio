import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

enum PaletteItemKind { command, file, symbol }

class PaletteItem {
  const PaletteItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.onSelect,
    this.subtitle,
    this.icon,
    this.keywords = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final PaletteItemKind kind;
  final List<String> keywords;
  final VoidCallback onSelect;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    if (title.toLowerCase().contains(needle)) return true;
    if (subtitle != null && subtitle!.toLowerCase().contains(needle)) {
      return true;
    }
    return keywords.any((item) => item.toLowerCase().contains(needle));
  }
}

typedef PaletteQuerySearcher = Future<List<PaletteItem>> Function(String query);

Future<void> showCommandPalette({
  required BuildContext context,
  required List<PaletteItem> commands,
  PaletteQuerySearcher? searchWorkspace,
  String hintText = 'Type a command, file, or symbol…',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => _CommandPaletteDialog(
      commands: commands,
      searchWorkspace: searchWorkspace,
      hintText: hintText,
    ),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.commands,
    required this.hintText,
    this.searchWorkspace,
  });

  final List<PaletteItem> commands;
  final PaletteQuerySearcher? searchWorkspace;
  final String hintText;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<PaletteItem> _dynamicItems = [];
  bool _searching = false;
  int _selectedIndex = 0;
  Timer? _debounce;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<PaletteItem> get _visibleItems {
    final query = _controller.text;
    final commands = widget.commands
        .where((item) => item.matches(query))
        .toList();
    if (query.trim().isEmpty) {
      return commands.take(12).toList();
    }
    return [...commands, ..._dynamicItems];
  }

  void _onQueryChanged() {
    setState(() => _selectedIndex = 0);
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty || widget.searchWorkspace == null) {
      setState(() {
        _dynamicItems = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_runWorkspaceSearch(query));
    });
  }

  Future<void> _runWorkspaceSearch(String query) async {
    final generation = ++_searchGeneration;
    setState(() => _searching = true);
    try {
      final results = await widget.searchWorkspace!(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _dynamicItems = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _dynamicItems = [];
        _searching = false;
      });
    }
  }

  void _activate(PaletteItem item) {
    Navigator.of(context).pop();
    item.onSelect();
  }

  void _moveSelection(int delta) {
    final items = _visibleItems;
    if (items.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, items.length - 1);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final items = _visibleItems;
      if (items.isNotEmpty) {
        _activate(items[_selectedIndex.clamp(0, items.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    final selected = items.isEmpty
        ? 0
        : _selectedIndex.clamp(0, items.length - 1);

    return Focus(
      onKeyEvent: _onKey,
      child: Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.only(top: 72, left: 48, right: 48),
        backgroundColor: context.palette.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: context.palette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _controller.text.trim().isEmpty
                              ? 'Start typing to filter commands.'
                              : 'No matching commands, files, or symbols.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = index == selected;
                          return Material(
                            color: isSelected
                                ? context.palette.accentSoft
                                : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              selected: isSelected,
                              leading: Icon(
                                item.icon ?? _iconFor(item.kind),
                                size: 18,
                                color: isSelected
                                    ? context.palette.accent
                                    : context.palette.textSecondary,
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: item.subtitle == null
                                  ? null
                                  : Text(
                                      item.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: Text(
                                _kindLabel(item.kind),
                                style: TextStyle(
                                  color: context.palette.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => _activate(item),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '↑↓ navigate  ·  Enter open  ·  Esc close',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text('⌘K', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PaletteItemKind kind) {
    return switch (kind) {
      PaletteItemKind.command => Icons.terminal,
      PaletteItemKind.file => Icons.description_outlined,
      PaletteItemKind.symbol => Icons.code,
    };
  }

  String _kindLabel(PaletteItemKind kind) {
    return switch (kind) {
      PaletteItemKind.command => 'CMD',
      PaletteItemKind.file => 'FILE',
      PaletteItemKind.symbol => 'SYMBOL',
    };
  }
}
