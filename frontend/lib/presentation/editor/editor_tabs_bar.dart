import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/theme/app_theme.dart';

class EditorTabsBar extends StatelessWidget {
  const EditorTabsBar({
    super.key,
    required this.tabs,
    required this.activePath,
    required this.onSelect,
    required this.onClose,
  });

  final List<EditorTabInfo> tabs;
  final String? activePath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
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
            active: active,
            onSelect: () => onSelect(tab.path),
            onClose: () => onClose(tab.path),
          );
        },
      ),
    );
  }
}

class _EditorTabChip extends StatefulWidget {
  const _EditorTabChip({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final EditorTabInfo tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_EditorTabChip> createState() => _EditorTabChipState();
}

class _EditorTabChipState extends State<_EditorTabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final bg = active
        ? AppColors.background
        : _hovered
            ? AppColors.surfaceHover
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
                    const Padding(
                      padding: EdgeInsets.only(right: AppSpacing.xs + 2),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: AppColors.accent,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      tab.fileName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
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
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.textMuted,
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
    );
  }
}
