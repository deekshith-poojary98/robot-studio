import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/sidebar_button.dart';
import 'sidebar_panel.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.activePanel,
    required this.onPanelSelected,
    this.onSettings,
  });

  final SidebarPanel activePanel;
  final ValueChanged<SidebarPanel> onPanelSelected;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      decoration: const BoxDecoration(
        color: AppColors.rail,
        border: Border(
          right: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Icon(
              Icons.crop_square_rounded,
              size: 16,
              color: AppColors.accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final panel in SidebarPanel.values)
                  SidebarButton(
                    icon: panel.icon,
                    label: panel.label,
                    isActive: panel == activePanel,
                    onTap: () => onPanelSelected(panel),
                  ),
              ],
            ),
          ),
          SidebarButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isActive: false,
            onTap: onSettings ?? () {},
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
