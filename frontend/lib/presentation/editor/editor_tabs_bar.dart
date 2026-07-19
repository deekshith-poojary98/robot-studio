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
          return InkWell(
            onTap: () => onSelect(tab.path),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: active ? AppColors.background : Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isDirty)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.circle, size: 8, color: AppColors.accent),
                    ),
                  Flexible(
                    child: Text(
                      tab.fileName,
                      overflow: TextOverflow.ellipsis,
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
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onClose(tab.path),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
