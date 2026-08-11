import 'package:flutter/material.dart';

enum SidebarPanel {
  explorer(
    'Explorer',
    Icons.account_tree_outlined,
    'Explorer — projects, environments, and files',
  ),
  search('Search', Icons.search, 'Search — find text across the project'),
  insights(
    'Insights',
    Icons.insights_outlined,
    'Insights — project composition and run health',
  ),
  libraries(
    'Libraries',
    Icons.menu_book_outlined,
    'Libraries — browse keywords, docs, and arguments',
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

  /// Kept in the enum and fully wired — hidden from the activity bar for beta
  /// until the extension UX is ready for users.
  plugins(
    'Plugins',
    Icons.extension_outlined,
    'Plugins — built-in and project extensions',
    showInActivityBar: false,
  ),
  sourceControl(
    'Source Control',
    Icons.call_split_outlined,
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
    'Robot Doctor — structural problems across the project',
  );

  const SidebarPanel(
    this.label,
    this.icon,
    this.tooltip, {
    this.showInActivityBar = true,
  });

  final String label;
  final IconData icon;
  final String tooltip;

  /// When false, the rail omits this panel (code + palette entry can remain).
  final bool showInActivityBar;

  /// Panels shown in the left activity bar.
  static Iterable<SidebarPanel> get activityBarPanels =>
      values.where((panel) => panel.showInActivityBar);
}
