import 'package:flutter/material.dart';

import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../execution/execution_console.dart';
import '../panels/problems_panel.dart';

enum BottomPanelTab {
  console('Console'),
  executionLogs('Execution Logs'),
  problems('Problems'),
  output('Output'),
  terminal('Terminal');

  const BottomPanelTab(this.label);
  final String label;
}

class BottomPanel extends StatefulWidget {
  const BottomPanel({
    super.key,
    this.logLines = const [],
    this.executionLines = const [],
    this.problems = const [],
    this.isLoadingProblems = false,
    this.problemCount = 0,
    this.forceExecutionTab = false,
    this.onProblemSelected,
  });

  final List<String> logLines;
  final List<String> executionLines;
  final List<DiagnosticInfo> problems;
  final bool isLoadingProblems;
  final int problemCount;
  final bool forceExecutionTab;
  final ValueChanged<DiagnosticInfo>? onProblemSelected;

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  BottomPanelTab _activeTab = BottomPanelTab.console;
  bool _expanded = true;
  double _height = 180;

  @override
  void didUpdateWidget(covariant BottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceExecutionTab &&
        widget.executionLines.length > oldWidget.executionLines.length) {
      _activeTab = BottomPanelTab.executionLogs;
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return _CollapsedBar(
        activeLabel: _activeTab.label,
        onExpand: () => setState(() => _expanded = true),
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
              color: AppColors.borderSubtle,
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 2,
                color: AppColors.border,
              ),
            ),
          ),
        ),
        Container(
          height: _height,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabBar(
                activeTab: _activeTab,
                problemCount: widget.problemCount,
                onTabSelected: (tab) => setState(() => _activeTab = tab),
                onCollapse: () => setState(() => _expanded = false),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_activeTab == BottomPanelTab.console) {
      return _LogView(
        lines: widget.logLines.isEmpty
            ? const [
                '[info] Robot Studio ready.',
                '[info] Connect a workspace to get started.',
              ]
            : widget.logLines,
      );
    }

    if (_activeTab == BottomPanelTab.executionLogs) {
      return ColoredBox(
        color: AppColors.rail,
        child: ExecutionConsole(lines: widget.executionLines),
      );
    }

    if (_activeTab == BottomPanelTab.problems) {
      return ProblemsPanel(
        diagnostics: widget.problems,
        isLoading: widget.isLoadingProblems,
        onSelect: widget.onProblemSelected ?? (_) {},
      );
    }

    return Center(
      child: Text(
        '${_activeTab.label} panel — coming in a later milestone.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _CollapsedBar extends StatelessWidget {
  const _CollapsedBar({
    required this.activeLabel,
    required this.onExpand,
  });

  final String activeLabel;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onExpand,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
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
              color: isActive ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.5,
            color: isActive ? AppColors.textPrimary : AppColors.textMuted,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final color = line.contains('[error]')
            ? AppColors.error
            : line.contains('[warn]')
                ? AppColors.warning
                : line.contains('[PASS]') || line.contains('[pass]')
                    ? AppColors.success
                    : AppColors.textSecondary;

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              color: color,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }
}
