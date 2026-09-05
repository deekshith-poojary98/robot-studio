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
  }) : super(height: kAppMenuItemHeight, padding: kAppMenuItemPadding);

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
          // Colour comes from IconTheme so the row follows the active theme.
          Icon(icon, size: 15),
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

/// Compact checked row for project / environment / run-config menus.
///
/// Material [CheckedPopupMenuItem] builds a [ListTile], which keeps a 48px+
/// tap target and ignores [kAppMenuItemHeight].
class AppCheckedPopupMenuItem<T> extends AppPopupMenuItem<T> {
  AppCheckedPopupMenuItem({
    super.key,
    super.value,
    required bool checked,
    required Widget child,
    super.enabled = true,
  }) : super(
         child: _CheckedMenuRow(checked: checked, child: child),
       );
}

class _CheckedMenuRow extends StatelessWidget {
  const _CheckedMenuRow({required this.checked, required this.child});

  final bool checked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: checked ? const Icon(Icons.check, size: 14) : null,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: child),
      ],
    );
  }
}

/// Visible hairline between menu groups (not empty vertical padding).
///
/// Resolves its colour in `build` rather than in the constructor so it stays
/// `const`-constructible at every call site while still following the theme.
class AppPopupMenuDivider extends PopupMenuEntry<Never> {
  const AppPopupMenuDivider({super.key});

  @override
  double get height => 9;

  @override
  bool represents(void value) => false;

  @override
  State<AppPopupMenuDivider> createState() => _AppPopupMenuDividerState();
}

class _AppPopupMenuDividerState extends State<AppPopupMenuDivider> {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: widget.height,
      thickness: 1,
      color: context.palette.border,
    );
  }
}
