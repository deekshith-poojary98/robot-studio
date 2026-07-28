import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Compact IDE-style menu row height (Material default is 48).
const double kAppMenuItemHeight = 28;

const EdgeInsets kAppMenuItemPadding = EdgeInsets.symmetric(horizontal: 10);

/// Compact [PopupMenuItem] for toolbars and explorer context menus.
class AppPopupMenuItem<T> extends PopupMenuItem<T> {
  const AppPopupMenuItem({
    super.key,
    super.value,
    required super.child,
    super.enabled = true,
    super.onTap,
  }) : super(
          height: kAppMenuItemHeight,
          padding: kAppMenuItemPadding,
        );

  /// Label + optional leading icon in one compact row.
  factory AppPopupMenuItem.icon({
    Key? key,
    required T value,
    required IconData icon,
    required String label,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return AppPopupMenuItem<T>(
      key: key,
      value: value,
      enabled: enabled,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class AppCheckedPopupMenuItem<T> extends CheckedPopupMenuItem<T> {
  const AppCheckedPopupMenuItem({
    super.key,
    super.value,
    required super.checked,
    required super.child,
    super.enabled = true,
  }) : super(
          height: kAppMenuItemHeight,
          padding: kAppMenuItemPadding,
        );
}

class AppPopupMenuDivider extends PopupMenuDivider {
  /// Visible hairline between menu groups (not empty vertical padding).
  const AppPopupMenuDivider({super.key})
      : super(
          height: 9,
          thickness: 1,
          color: AppColors.border,
        );
}
