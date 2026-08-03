import 'package:flutter/material.dart';

enum SidebarPanel {
  explorer(
    'Explorer',
    Icons.account_tree_outlined,
    'Explorer — projects, environments, and files',
  ),
  search(
    'Search',
    Icons.search,
    'Search — find text across the project',
  ),
  tests(
    'Tests',
    Icons.science_outlined,
    'Tests — browse, run, and track suites and tests',
  ),
  packages(
    'Packages',
    Icons.inventory_2_outlined,
    'Packages — install and manage Python packages',
  ),
  plugins(
    'Plugins',
    Icons.extension_outlined,
    'Plugins — built-in and project extensions',
  ),
  sourceControl(
    'Source Control',
    Icons.source_outlined,
    'Source Control — Git status, commit, and branches',
  ),
  reports(
    'Reports',
    Icons.bar_chart_outlined,
    'Reports — run history, logs, and HTML reports',
  ),
  doctor(
    'Doctor',
    Icons.health_and_safety_outlined,
    'Robot Doctor — project health and prioritized findings',
  );

  const SidebarPanel(this.label, this.icon, this.tooltip);

  final String label;
  final IconData icon;
  final String tooltip;
}
