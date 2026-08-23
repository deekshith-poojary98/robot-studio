import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/models/doctor_info.dart';
import '../../core/gateway/transport_gateway.dart';
import '../../core/theme/app_theme.dart';
import '../shell/controllers/workspace_live_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/timed_loading_indicator.dart';

typedef DoctorJumpToSource =
    void Function(String path, {int? line, int? column});

/// First-class Project Health Center — not a Problems panel.
class DoctorPage extends StatefulWidget {
  const DoctorPage({super.key, required this.gateway, this.onJumpToSource});

  final TransportGateway gateway;
  final DoctorJumpToSource? onJumpToSource;

  @override
  State<DoctorPage> createState() => DoctorPageState();
}

enum _SortMode { priority, severity, category, file }

class DoctorPageState extends State<DoctorPage> {
  bool _loading = true;
  bool _running = false;
  String? _error;
  DoctorReport? _report;

  String _search = '';
  String? _severityFilter; // null = all
  String? _categoryFilter;
  _SortMode _sort = _SortMode.priority;
  String? _expandedFindingId;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _runDoctor(initial: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Removes cached findings for paths deleted from the workspace.
  void pruneRemovedPaths(String path, {bool isDirectory = false}) {
    final report = _report;
    if (report == null || path.trim().isEmpty) return;
    final updated = doctorReportWithoutRemovedPaths(
      report,
      [path],
      pathsEqual: WorkspaceLiveController.pathsEqual,
      isDirectory: isDirectory,
    );
    if (updated.findings.length == report.findings.length) return;
    if (!mounted) return;
    setState(() {
      _report = updated;
      final expanded = _expandedFindingId;
      if (expanded != null &&
          !updated.findings.any((finding) => finding.id == expanded)) {
        _expandedFindingId = null;
      }
    });
  }

  Future<void> _runDoctor({bool initial = false}) async {
    setState(() {
      _running = true;
      if (initial) _loading = true;
      _error = null;
    });
    try {
      final report = await widget.gateway.runDoctor(profile: 'default');
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
        _loading = false;
        _expandedFindingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<DoctorFinding> get _visibleFindings {
    final report = _report;
    if (report == null) return const [];
    var items = List<DoctorFinding>.from(report.findings);
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items
          .where(
            (f) =>
                f.message.toLowerCase().contains(q) ||
                f.filePath.toLowerCase().contains(q) ||
                (f.category ?? '').toLowerCase().contains(q) ||
                f.inspectionId.toLowerCase().contains(q) ||
                f.rationale.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_severityFilter != null) {
      items = items.where((f) => f.severity == _severityFilter).toList();
    }
    if (_categoryFilter != null) {
      items = items.where((f) => f.category == _categoryFilter).toList();
    }
    int sevRank(String s) => switch (s) {
      'error' => 4,
      'warning' => 3,
      'info' => 2,
      'hint' => 1,
      _ => 0,
    };
    switch (_sort) {
      case _SortMode.priority:
        // Keep server priority order (already sorted), just filtered.
        break;
      case _SortMode.severity:
        items.sort(
          (a, b) => sevRank(b.severity).compareTo(sevRank(a.severity)),
        );
      case _SortMode.category:
        items.sort((a, b) => (a.category ?? '').compareTo(b.category ?? ''));
      case _SortMode.file:
        items.sort((a, b) => a.filePath.compareTo(b.filePath));
    }
    return items;
  }

  Map<String, List<DoctorFinding>> get _groupedVisible {
    final map = <String, List<DoctorFinding>>{};
    for (final f in _visibleFindings) {
      final key = f.category ?? 'maintainability';
      map.putIfAbsent(key, () => []).add(f);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            running: _running,
            onRun: _running ? null : () => unawaited(_runDoctor()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.palette.error),
              ),
            ),
          if (_report != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: _HealthSummaryStrip(report: _report!),
            ),
          if (_report != null && _report!.topRecommendations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: _RecommendationsStrip(
                recommendations: _report!.topRecommendations,
                onSelect: (id) => setState(() => _expandedFindingId = id),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: _FilterBar(
              search: _search,
              severityFilter: _severityFilter,
              categoryFilter: _categoryFilter,
              sort: _sort,
              categories: _report?.summary.byCategory.keys.toList() ?? const [],
              onSearch: (v) => setState(() => _search = v),
              onSeverity: (v) => setState(() => _severityFilter = v),
              onCategory: (v) => setState(() => _categoryFilter = v),
              onSort: (v) => setState(() => _sort = v),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading || (_running && _report == null)
                ? const TimedLoadingIndicator()
                : _report == null
                ? EmptyState(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Run Robot Doctor',
                    message:
                        'Scan the project for structural problems across files — '
                        'circular imports, duplicate keywords, and potentially unused assets.',
                    actionLabel: 'Scan project',
                    onAction: () => unawaited(_runDoctor()),
                  )
                : _visibleFindings.isEmpty
                ? EmptyState(
                    icon: Icons.verified_outlined,
                    title: _report!.findings.isEmpty
                        ? 'No structural problems found'
                        : 'No matching findings',
                    message: _report!.findings.isEmpty
                        ? 'Circular imports, duplicate keywords, and potentially '
                              'unused assets look clear. File-level issues still '
                              'appear in Problems.'
                        : 'Adjust filters or search to see more findings.',
                  )
                : _FindingsList(
                    grouped: _groupedVisible,
                    expandedId: _expandedFindingId,
                    onToggle: (id) => setState(() {
                      _expandedFindingId = _expandedFindingId == id ? null : id;
                    }),
                    onJump: widget.onJumpToSource,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.running, required this.onRun});

  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        20,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Robot Doctor',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Structural problems across the project — circular imports, '
                  'duplicate keywords, potentially unused assets.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(running ? 'Scanning…' : 'Scan project'),
          ),
        ],
      ),
    );
  }
}

class _HealthSummaryStrip extends StatelessWidget {
  const _HealthSummaryStrip({required this.report});

  final DoctorReport report;

  @override
  Widget build(BuildContext context) {
    final s = report.summary;
    final trend = s.improvementTrend;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatChip(label: 'Findings', value: '${s.totalFindings}'),
          _StatChip(
            label: 'Blockers',
            value: '${s.criticalIssues}',
            emphasize: s.criticalIssues > 0,
          ),
          _StatChip(label: 'Info', value: '${s.bySeverity['info'] ?? 0}'),
          if (trend != null)
            _StatChip(
              label: 'Since last scan',
              value: _trendLabel(trend),
              emphasize: trend.improved || trend.deltaTotal > 0,
              positive: trend.improved,
            ),
        ],
      ),
    );
  }
}

String _trendLabel(DoctorImprovementTrend trend) {
  if (trend.deltaTotal == 0) return 'Same findings';
  if (trend.deltaTotal < 0) {
    final n = -trend.deltaTotal;
    return '$n fewer';
  }
  return '${trend.deltaTotal} more';
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.positive = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? context.palette.success
        : emphasize
        ? context.palette.error
        : context.palette.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.palette.textMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: color, fontSize: 14),
        ),
      ],
    );
  }
}

class _RecommendationsStrip extends StatelessWidget {
  const _RecommendationsStrip({
    required this.recommendations,
    required this.onSelect,
  });

  final List<DoctorRecommendation> recommendations;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fix first', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ...recommendations.take(3).map((r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: InkWell(
              onTap: () => onSelect(r.findingId),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: context.palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: context.palette.borderSubtle),
                ),
                child: Row(
                  children: [
                    Text(
                      '#${r.rank}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.palette.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        r.finding.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        r.reason,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.severityFilter,
    required this.categoryFilter,
    required this.sort,
    required this.categories,
    required this.onSearch,
    required this.onSeverity,
    required this.onCategory,
    required this.onSort,
  });

  final String search;
  final String? severityFilter;
  final String? categoryFilter;
  final _SortMode sort;
  final List<String> categories;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onSeverity;
  final ValueChanged<String?> onCategory;
  final ValueChanged<_SortMode> onSort;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 32,
          child: TextField(
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              hintText: 'Search findings',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              prefixIcon: const Icon(Icons.search, size: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
            ),
            onChanged: onSearch,
          ),
        ),
        _FilterDropdown<String?>(
          label: 'Severity',
          value: severityFilter,
          items: const [
            (null, 'All'),
            ('error', 'Error'),
            ('warning', 'Warning'),
            ('info', 'Info'),
            ('hint', 'Hint'),
          ],
          onChanged: onSeverity,
        ),
        _FilterDropdown<String?>(
          label: 'Category',
          value: categoryFilter,
          items: [
            (null, 'All'),
            ...categories.map((c) => (c, _categoryLabel(c))),
          ],
          onChanged: onCategory,
        ),
        _FilterDropdown<_SortMode>(
          label: 'Sort',
          value: sort,
          items: const [
            (_SortMode.priority, 'Priority'),
            (_SortMode.severity, 'Severity'),
            (_SortMode.category, 'Category'),
            (_SortMode.file, 'File'),
          ],
          onChanged: onSort,
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: context.palette.textMuted),
        ),
        const SizedBox(width: AppSpacing.xs),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
            ),
            items: items
                .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null || items.any((e) => e.$1 == null)) {
                onChanged(v as T);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _FindingsList extends StatelessWidget {
  const _FindingsList({
    required this.grouped,
    required this.expandedId,
    required this.onToggle,
    this.onJump,
  });

  final Map<String, List<DoctorFinding>> grouped;
  final String? expandedId;
  final ValueChanged<String> onToggle;
  final DoctorJumpToSource? onJump;

  @override
  Widget build(BuildContext context) {
    final keys = grouped.keys.toList()
      ..sort((a, b) => _categoryRank(a).compareTo(_categoryRank(b)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final category = keys[index];
        final findings = grouped[category]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_categoryLabel(category)} (${findings.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_categoryHint(category) != null) ...[
                const SizedBox(height: 2),
                Text(
                  _categoryHint(category)!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              ...findings.map(
                (f) => _FindingTile(
                  finding: f,
                  expanded: expandedId == f.id,
                  onToggle: () => onToggle(f.id),
                  onJump: onJump,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({
    required this.finding,
    required this.expanded,
    required this.onToggle,
    this.onJump,
  });

  final DoctorFinding finding;
  final bool expanded;
  final VoidCallback onToggle;
  final DoctorJumpToSource? onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: expanded
            ? context.palette.surfaceElevated
            : context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          hoverColor: context.palette.surfaceHover,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: context.palette.borderSubtle),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SeverityBadge(severity: finding.severity),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        finding.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: expanded ? 4 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (finding.locationLabel.isNotEmpty)
                      Text(
                        finding.locationLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.md),
                  if (finding.cyclePath != null) ...[
                    Text(
                      'Import cycle',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(
                      finding.cyclePath!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    'Why this matters',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    finding.rationale.isEmpty
                        ? 'No additional detail from this check.'
                        : finding.rationale,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _confidenceExplanation(finding.confidence),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                  if (finding.affectedFiles.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Affected files',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...finding.affectedFiles.map((file) {
                      final label = '${file.path.split('/').last}:${file.line}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: InkWell(
                          onTap: onJump == null
                              ? null
                              : () => onJump!(
                                  file.path,
                                  line: file.line,
                                  column: 1,
                                ),
                          borderRadius: BorderRadius.circular(AppRadii.xs),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 2,
                              horizontal: 2,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 14,
                                  color: context.palette.textMuted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    '$label  ·  ${file.name}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: context.palette.accent,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (finding.filePath.isNotEmpty ||
                      finding.affectedFiles.isNotEmpty)
                    FilledButton.tonalIcon(
                      key: const Key('doctor-open-source'),
                      onPressed: onJump == null
                          ? null
                          : () {
                              final first = finding.affectedFiles.isNotEmpty
                                  ? finding.affectedFiles.first
                                  : (
                                      path: finding.filePath,
                                      name: '',
                                      line: finding.line,
                                    );
                              onJump!(
                                first.path,
                                line: first.line,
                                column: finding.column,
                              );
                            },
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open source'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      'error' => context.palette.error,
      'warning' => context.palette.warning,
      'info' => context.palette.info,
      _ => context.palette.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        severity.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _confidenceExplanation(String confidence) {
  final key = confidence.toLowerCase();
  if (key == 'exact' || key == 'high') {
    return 'Confidence: high — this structural check is usually reliable.';
  }
  if (key == 'medium') {
    return 'Confidence: medium — verify before deleting or refactoring.';
  }
  if (key == 'low') {
    return 'Confidence: low — double-check; this can be a false alarm.';
  }
  return 'Confidence: $confidence';
}

String _categoryLabel(String category) {
  return switch (category) {
    'correctness' => 'Duplicate keywords',
    'maintainability' => 'Potentially unused',
    'dependencies' => 'Circular imports',
    _ => category,
  };
}

String? _categoryHint(String category) {
  return switch (category) {
    'correctness' => 'Same keyword name defined in more than one place.',
    'maintainability' =>
      'No static callers/imports found — confirm before deleting.',
    'dependencies' => 'Resources or suites that import each other in a cycle.',
    _ => null,
  };
}

int _categoryRank(String category) {
  const order = ['dependencies', 'correctness', 'maintainability'];
  final i = order.indexOf(category);
  return i < 0 ? 99 : i;
}
