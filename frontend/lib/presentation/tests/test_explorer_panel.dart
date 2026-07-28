import 'package:flutter/material.dart';

import '../../core/gateway/models/test_explorer_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_menu.dart';
import '../widgets/skeleton_list.dart';

typedef TestNodeCallback = void Function(TestNodeInfo node);

class TestExplorerPanel extends StatefulWidget {
  const TestExplorerPanel({
    super.key,
    required this.tree,
    this.isLoading = false,
    this.filter = '',
    this.onFilterChanged,
    this.onRefresh,
    this.onRunAll,
    this.onRunCurrentFile,
    this.onRunFailed,
    this.onRunNode,
    this.onOpenFile,
    this.onRevealInExplorer,
    this.currentFilePath,
  });

  final TestNodeInfo? tree;
  final bool isLoading;
  final String filter;
  final ValueChanged<String>? onFilterChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onRunAll;
  final VoidCallback? onRunCurrentFile;
  final VoidCallback? onRunFailed;
  final TestNodeCallback? onRunNode;
  final TestNodeCallback? onOpenFile;
  final TestNodeCallback? onRevealInExplorer;
  final String? currentFilePath;

  @override
  State<TestExplorerPanel> createState() => _TestExplorerPanelState();
}

class _TestExplorerPanelState extends State<TestExplorerPanel> {
  final Set<String> _expanded = {};
  final Set<String> _selected = {};
  final TextEditingController _filterController = TextEditingController();
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _filterController.text = widget.filter;
    _seedExpanded();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TestExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tree?.id != widget.tree?.id) {
      _seeded = false;
    }
    if (widget.filter != _filterController.text) {
      _filterController.value = TextEditingValue(
        text: widget.filter,
        selection: TextSelection.collapsed(offset: widget.filter.length),
      );
    }
    _seedExpanded();
  }

  void _seedExpanded() {
    final tree = widget.tree;
    if (tree == null || _seeded) return;
    // Seed defaults once per tree id; INDEX_UPDATED refreshes keep expand state
    // when the root id is stable.
    _expanded
      ..clear()
      ..add(tree.id);
    for (final project in tree.children) {
      _expanded.add(project.id);
      for (final suite in project.children.take(3)) {
        _expanded.add(suite.id);
      }
    }
    _seeded = true;
  }

  void _expandAll() {
    final tree = widget.tree;
    if (tree == null) return;
    setState(() {
      _expanded
        ..clear()
        ..addAll(_collectIds(tree));
    });
  }

  void _collapseAll() {
    final tree = widget.tree;
    setState(() {
      _expanded.clear();
      if (tree != null) {
        _expanded.add(tree.id);
      }
    });
  }

  Iterable<String> _collectIds(TestNodeInfo node) sync* {
    yield node.id;
    for (final child in node.children) {
      yield* _collectIds(child);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          onRunAll: widget.onRunAll,
          onRunCurrentFile: widget.onRunCurrentFile,
          onRunFailed: widget.onRunFailed,
          onRefresh: widget.onRefresh,
          onExpandAll: _expandAll,
          onCollapseAll: _collapseAll,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: TextField(
            key: const Key('test-explorer-search'),
            controller: _filterController,
            onChanged: widget.onFilterChanged,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter suites, tests, tags, files…',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 28,
              ),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                borderSide: const BorderSide(color: AppColors.borderSubtle),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
          ),
        ),
        Expanded(
          child: widget.isLoading && widget.tree == null
              ? const SkeletonList(rows: 6)
              : widget.tree == null
                  ? const EmptyState(
                      icon: Icons.science_outlined,
                      title: 'No tests yet',
                      message: 'Open a project to browse suites and cases.',
                      compact: true,
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        _TestTreeNodeTile(
                          node: widget.tree!,
                          depth: 0,
                          expanded: _expanded,
                          selected: _selected,
                          onToggle: (id) {
                            setState(() {
                              if (_expanded.contains(id)) {
                                _expanded.remove(id);
                              } else {
                                _expanded.add(id);
                              }
                            });
                          },
                          onSelect: (node) {
                            setState(() {
                              if (_selected.contains(node.id)) {
                                _selected.remove(node.id);
                              } else {
                                _selected.add(node.id);
                              }
                            });
                          },
                          onRunNode: widget.onRunNode,
                          onOpenFile: widget.onOpenFile,
                          onRevealInExplorer: widget.onRevealInExplorer,
                        ),
                      ],
                    ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    this.onRunAll,
    this.onRunCurrentFile,
    this.onRunFailed,
    this.onRefresh,
    this.onExpandAll,
    this.onCollapseAll,
  });

  final VoidCallback? onRunAll;
  final VoidCallback? onRunCurrentFile;
  final VoidCallback? onRunFailed;
  final VoidCallback? onRefresh;
  final VoidCallback? onExpandAll;
  final VoidCallback? onCollapseAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          _ToolIcon(
            key: const Key('test-run-all'),
            icon: Icons.play_arrow,
            tooltip: 'Run All',
            onPressed: onRunAll,
          ),
          _ToolIcon(
            key: const Key('test-run-current-file'),
            icon: Icons.play_circle_outline,
            tooltip: 'Run Current File',
            onPressed: onRunCurrentFile,
          ),
          _ToolIcon(
            key: const Key('test-run-failed'),
            icon: Icons.replay,
            tooltip: 'Run Failed',
            onPressed: onRunFailed,
          ),
          _ToolIcon(
            key: const Key('test-refresh'),
            icon: Icons.refresh,
            tooltip: 'Refresh Tests',
            onPressed: onRefresh,
          ),
          _ToolIcon(
            key: const Key('test-collapse-all'),
            icon: Icons.unfold_less,
            tooltip: 'Collapse All',
            onPressed: onCollapseAll,
          ),
          _ToolIcon(
            key: const Key('test-expand-all'),
            icon: Icons.unfold_more,
            tooltip: 'Expand All',
            onPressed: onExpandAll,
          ),
        ],
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      color: AppColors.textSecondary,
    );
  }
}

class _TestTreeNodeTile extends StatelessWidget {
  const _TestTreeNodeTile({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
    this.onRunNode,
    this.onOpenFile,
    this.onRevealInExplorer,
  });

  final TestNodeInfo node;
  final int depth;
  final Set<String> expanded;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final TestNodeCallback onSelect;
  final TestNodeCallback? onRunNode;
  final TestNodeCallback? onOpenFile;
  final TestNodeCallback? onRevealInExplorer;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = expanded.contains(node.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected.contains(node.id)
              ? AppColors.accentSoft
              : Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(node),
            onDoubleTap: node.path == null
                ? null
                : () => onOpenFile?.call(node),
            onSecondaryTapDown: (details) => _showMenu(context, details),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8.0 + depth * 12, 3, 6, 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: hasChildren
                        ? GestureDetector(
                            onTap: () => onToggle(node.id),
                            child: Icon(
                              isExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Icon(_kindIcon(node.kind), size: 14, color: _kindColor(node)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.2,
                        color: AppColors.textPrimary,
                        fontStyle: node.kind == 'setup' || node.kind == 'teardown'
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (node.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        node.tags.take(2).join(','),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  _StatusDot(status: node.status),
                  if (node.isRunnable)
                    IconButton(
                      key: Key('test-run-${node.id}'),
                      onPressed: onRunNode == null
                          ? null
                          : () => onRunNode!(node),
                      tooltip: 'Run',
                      icon: const Icon(Icons.play_arrow, size: 14),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      padding: EdgeInsets.zero,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasChildren && isExpanded)
          for (final child in node.children)
            _TestTreeNodeTile(
              node: child,
              depth: depth + 1,
              expanded: expanded,
              selected: selected,
              onToggle: onToggle,
              onSelect: onSelect,
              onRunNode: onRunNode,
              onOpenFile: onOpenFile,
              onRevealInExplorer: onRevealInExplorer,
            ),
      ],
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        if (node.isRunnable)
          const AppPopupMenuItem(value: 'run', child: Text('Run')),
        if (node.path != null)
          const AppPopupMenuItem(value: 'open', child: Text('Open File')),
        if (node.path != null)
          const AppPopupMenuItem(
            value: 'reveal',
            child: Text('Reveal in Explorer'),
          ),
      ],
    );
    if (selected == 'run') onRunNode?.call(node);
    if (selected == 'open') onOpenFile?.call(node);
    if (selected == 'reveal') onRevealInExplorer?.call(node);
  }

  static IconData _kindIcon(String kind) {
    return switch (kind) {
      'workspace' => Icons.work_outline,
      'project' => Icons.folder_outlined,
      'suite' => Icons.description_outlined,
      'test' => Icons.science_outlined,
      'task' => Icons.checklist_outlined,
      'setup' => Icons.settings_suggest_outlined,
      'teardown' => Icons.settings_backup_restore_outlined,
      _ => Icons.circle_outlined,
    };
  }

  static Color _kindColor(TestNodeInfo node) {
    if (node.status == TestNodeStatus.running) return AppColors.info;
    if (node.status == TestNodeStatus.fail) return AppColors.error;
    if (node.status == TestNodeStatus.pass) return AppColors.success;
    return AppColors.textSecondary;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final TestNodeStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TestNodeStatus.pass => AppColors.success,
      TestNodeStatus.fail => AppColors.error,
      TestNodeStatus.skip => AppColors.warning,
      TestNodeStatus.running => AppColors.info,
      TestNodeStatus.notRun => AppColors.textMuted,
    };
    return Tooltip(
      message: status.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: status == TestNodeStatus.running
            ? SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  color: color,
                ),
              )
            : Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}
