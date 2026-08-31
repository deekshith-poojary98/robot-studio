import 'package:flutter/material.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../panels/problems_panel.dart';
import '../panels/terminal_panel.dart';

enum BottomPanelTab {
  terminal('Terminal'),
  problems('Problems');

  const BottomPanelTab(this.label);
  final String label;
}

class BottomPanel extends StatefulWidget {
  const BottomPanel({
    super.key,
    this.problems = const [],
    this.isLoadingProblems = false,
    this.problemCount = 0,
    this.workingDirectory,
    this.revealTerminalToken,
    this.toggleTerminalToken,
    this.revealProblemsToken,
    this.onProblemSelected,
    this.onProblemQuickFix,
    this.preferCollapsed = false,
  });

  final List<DiagnosticInfo> problems;
  final bool isLoadingProblems;
  final int problemCount;
  final String? workingDirectory;
  final int? revealTerminalToken;

  /// Flip Terminal open/closed (⌘` / Ctrl+`).
  final int? toggleTerminalToken;
  final int? revealProblemsToken;
  final ValueChanged<DiagnosticInfo>? onProblemSelected;
  final ValueChanged<DiagnosticInfo>? onProblemQuickFix;

  /// When this becomes true (e.g. entering the welcome page), collapse the panel.
  final bool preferCollapsed;

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  BottomPanelTab _activeTab = BottomPanelTab.terminal;
  bool _expanded = false;
  double _height = 180;

  /// True only when Problems was expanded because diagnostics appeared.
  /// Manual open (menu, status bar, tabs, collapsed bar) must not auto-close.
  bool _problemsAutoOpened = false;

  @override
  void initState() {
    super.initState();
    // Start collapsed. Reveal/toggle tokens only expand via [didUpdateWidget]
    // when they *change* — an initial `0` must not open the panel on launch.
  }

  void _markUserOpenedPanel() {
    _problemsAutoOpened = false;
  }

  @override
  void didUpdateWidget(covariant BottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferCollapsed && !oldWidget.preferCollapsed) {
      _expanded = false;
      _problemsAutoOpened = false;
    }
    if (widget.revealTerminalToken != null &&
        widget.revealTerminalToken != oldWidget.revealTerminalToken) {
      _activeTab = BottomPanelTab.terminal;
      _expanded = true;
      _markUserOpenedPanel();
    }
    if (widget.toggleTerminalToken != null &&
        widget.toggleTerminalToken != oldWidget.toggleTerminalToken) {
      _markUserOpenedPanel();
      if (_activeTab == BottomPanelTab.terminal && _expanded) {
        _expanded = false;
      } else {
        _activeTab = BottomPanelTab.terminal;
        _expanded = true;
      }
    }
    if (widget.revealProblemsToken != null &&
        widget.revealProblemsToken != oldWidget.revealProblemsToken) {
      _activeTab = BottomPanelTab.problems;
      _expanded = true;
      _markUserOpenedPanel();
    }
    // Auto-open Problems when diagnostics first appear while editing.
    if (widget.problemCount > 0 &&
        oldWidget.problemCount == 0 &&
        widget.problems.isNotEmpty) {
      _problemsAutoOpened = !_expanded;
      _activeTab = BottomPanelTab.problems;
      _expanded = true;
    }
    // Auto-close only while Problems is still the visible tab. If the user
    // switched to Terminal (or otherwise took over the panel), leave it open.
    if (oldWidget.problemCount > 0 &&
        widget.problemCount == 0 &&
        _problemsAutoOpened &&
        _activeTab == BottomPanelTab.problems) {
      _expanded = false;
      _problemsAutoOpened = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return _CollapsedBar(
        activeLabel: _activeTab.label,
        problemCount: widget.problemCount,
        onExpand: () => setState(() {
          _expanded = true;
          _markUserOpenedPanel();
        }),
        onOpenProblems: widget.problemCount > 0
            ? () => setState(() {
                _activeTab = BottomPanelTab.problems;
                _expanded = true;
                _markUserOpenedPanel();
              })
            : null,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                _height = (_height - details.delta.dy).clamp(110.0, 420.0);
              });
            },
            child: Container(
              height: 4,
              color: context.palette.borderSubtle,
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 2,
                color: context.palette.border,
              ),
            ),
          ),
        ),
        Container(
          height: _height,
          decoration: BoxDecoration(
            color: context.palette.surface,
            border: Border(
              top: BorderSide(color: context.palette.borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabBar(
                activeTab: _activeTab,
                problemCount: widget.problemCount,
                onTabSelected: (tab) => setState(() {
                  _activeTab = tab;
                  _markUserOpenedPanel();
                }),
                onCollapse: () => setState(() {
                  _expanded = false;
                  _problemsAutoOpened = false;
                }),
              ),
              // Keep Terminal mounted so the shell survives tab switches.
              Expanded(
                child: IndexedStack(
                  index: _activeTab.index,
                  sizing: StackFit.expand,
                  children: [
                    TerminalPanel(workingDirectory: widget.workingDirectory),
                    ProblemsPanel(
                      diagnostics: widget.problems,
                      isLoading: widget.isLoadingProblems,
                      onSelect: widget.onProblemSelected ?? (_) {},
                      onQuickFix: widget.onProblemQuickFix,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({
    required this.activeLabel,
    required this.onExpand,
    this.problemCount = 0,
    this.onOpenProblems,
  });

  final String activeLabel;
  final VoidCallback onExpand;
  final int problemCount;
  final VoidCallback? onOpenProblems;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onExpand,
              child: Row(
                children: [
                  Text(
                    activeLabel.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const Spacer(),
                  const Icon(Icons.keyboard_arrow_up, size: 16),
                ],
              ),
            ),
          ),
          if (problemCount > 0) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onOpenProblems,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'PROBLEMS $problemCount',
                  style: TextStyle(
                    color: context.palette.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.activeTab,
    required this.problemCount,
    required this.onTabSelected,
    required this.onCollapse,
  });

  final BottomPanelTab activeTab;
  final int problemCount;
  final ValueChanged<BottomPanelTab> onTabSelected;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Row(
        children: [
          ...BottomPanelTab.values.map((tab) {
            final label = tab == BottomPanelTab.problems && problemCount > 0
                ? '${tab.label} ($problemCount)'
                : tab.label;
            return _Tab(
              label: label,
              isActive: activeTab == tab,
              onTap: () => onTabSelected(tab),
            );
          }),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            onPressed: onCollapse,
            tooltip: 'Collapse panel',
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? context.palette.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.5,
            color: isActive
                ? context.palette.textPrimary
                : context.palette.textMuted,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
