import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_menu.dart';
import '../workspace/explorer_file_actions.dart';

enum EditorTabContextAction {
  close,
  closeOthers,
  closeAll,
  closeSaved,
  closeToTheRight,
  revealInOs,
  copyRelativePath,
  copyAbsolutePath,
}

class EditorTabsBar extends StatelessWidget {
  const EditorTabsBar({
    super.key,
    required this.tabs,
    required this.activePath,
    required this.onSelect,
    required this.onClose,
    this.onContextAction,
  });

  final List<EditorTabInfo> tabs;
  final String? activePath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final void Function(String path, EditorTabContextAction action)?
  onContextAction;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const VerticalDivider(width: 1),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = tab.path == activePath;
          return _EditorTabChip(
            tab: tab,
            index: index,
            tabCount: tabs.length,
            active: active,
            onSelect: () => onSelect(tab.path),
            onClose: () => onClose(tab.path),
            onContextAction: onContextAction,
          );
        },
      ),
    );
  }
}

class _EditorTabChip extends StatefulWidget {
  const _EditorTabChip({
    required this.tab,
    required this.index,
    required this.tabCount,
    required this.active,
    required this.onSelect,
    required this.onClose,
    this.onContextAction,
  });

  final EditorTabInfo tab;
  final int index;
  final int tabCount;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(String path, EditorTabContextAction action)?
  onContextAction;

  @override
  State<_EditorTabChip> createState() => _EditorTabChipState();
}

class _EditorTabChipState extends State<_EditorTabChip> {
  bool _hovered = false;

  Future<void> _showMenu(Offset globalPosition) async {
    final onAction = widget.onContextAction;
    if (onAction == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final revealLabel = ExplorerFileActions.revealLabel();
    final hasOthers = widget.tabCount > 1;
    final hasToRight = widget.index < widget.tabCount - 1;

    final selected = await showMenu<EditorTabContextAction>(
      context: context,
      position: position,
      items: [
        const AppPopupMenuItem(
          value: EditorTabContextAction.close,
          child: Text('Close'),
        ),
        AppPopupMenuItem(
          value: EditorTabContextAction.closeOthers,
          enabled: hasOthers,
          child: const Text('Close Others'),
        ),
        const AppPopupMenuItem(
          value: EditorTabContextAction.closeAll,
          child: Text('Close All'),
        ),
        const AppPopupMenuItem(
          value: EditorTabContextAction.closeSaved,
          child: Text('Close Saved'),
        ),
        AppPopupMenuItem(
          value: EditorTabContextAction.closeToTheRight,
          enabled: hasToRight,
          child: const Text('Close to the Right'),
        ),
        const AppPopupMenuDivider(),
        AppPopupMenuItem(
          value: EditorTabContextAction.revealInOs,
          child: Text(revealLabel),
        ),
        const AppPopupMenuItem(
          value: EditorTabContextAction.copyRelativePath,
          child: Text('Copy Relative Path'),
        ),
        const AppPopupMenuItem(
          value: EditorTabContextAction.copyAbsolutePath,
          child: Text('Copy Absolute Path'),
        ),
      ],
    );

    if (!mounted || selected == null) return;
    onAction(widget.tab.path, selected);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final bg = active
        ? context.palette.background
        : _hovered
        ? context.palette.surfaceHover
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: active,
      label: '${tab.fileName}${tab.isDirty ? ', modified' : ''}',
      child: Tooltip(
        message: tab.path,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onSecondaryTapDown: (details) {
              widget.onSelect();
              unawaited(_showMenu(details.globalPosition));
            },
            child: InkWell(
              onTap: widget.onSelect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                color: bg,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.isDirty)
                      Padding(
                        padding: EdgeInsets.only(right: AppSpacing.xs + 2),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: context.palette.accent,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        tab.fileName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: active
                              ? context.palette.textPrimary
                              : context.palette.textSecondary,
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Semantics(
                      button: true,
                      label: 'Close ${tab.fileName}',
                      child: InkWell(
                        onTap: widget.onClose,
                        borderRadius: BorderRadius.circular(AppRadii.xs),
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: context.palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
