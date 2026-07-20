import 'package:flutter/material.dart';

enum SidebarPanel {
  explorer('Explorer', Icons.account_tree_outlined),
  search('Search', Icons.search),
  tests('Tests', Icons.science_outlined),
  keywords('Keywords', Icons.vpn_key_outlined),
  packages('Packages', Icons.inventory_2_outlined),
  plugins('Plugins', Icons.extension_outlined),
  sourceControl('Source Control', Icons.source_outlined),
  reports('Reports', Icons.bar_chart_outlined),
  ai('AI', Icons.auto_awesome_outlined);

  const SidebarPanel(this.label, this.icon);

  final String label;
  final IconData icon;
}
