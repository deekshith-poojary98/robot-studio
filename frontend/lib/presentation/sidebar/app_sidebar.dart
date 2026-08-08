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
    this.settingsActive = false,
    this.showBranding = true,
  });

  final SidebarPanel activePanel;
  final ValueChanged<SidebarPanel> onPanelSelected;
  final VoidCallback? onSettings;
  final bool settingsActive;
  final bool showBranding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: context.palette.rail,
        border: Border(right: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Tooltip(
            message: 'Robot Studio',
            child: Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: showBranding
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          Theme.of(context).brightness == Brightness.dark
                              ? 'assets/branding/logo-mark.png'
                              : 'assets/branding/logo-mark-light.png',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          cacheWidth: 60,
                          cacheHeight: 60,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                          semanticLabel: 'Robot Studio',
                        ),
                      )
                    : const SizedBox.expand(),
              ),
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
                    tooltip: panel.tooltip,
                    isActive: !settingsActive && panel == activePanel,
                    onTap: () => onPanelSelected(panel),
                  ),
              ],
            ),
          ),
          if (onSettings != null)
            SidebarButton(
              icon: Icons.settings_outlined,
              label: 'Settings',
              tooltip: 'Settings (⌘,)',
              isActive: settingsActive,
              onTap: onSettings!,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
