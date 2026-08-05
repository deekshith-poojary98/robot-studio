import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/models/doctor_info.dart';
import '../../core/gateway/transport_gateway.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';

typedef DoctorJumpToSource =
    void Function(String path, {int? line, int? column});

/// First-class Project Health Center — not a Problems panel.
class DoctorPage extends StatefulWidget {
  const DoctorPage({super.key, required this.gateway, this.onJumpToSource});

  final TransportGateway gateway;
  final DoctorJumpToSource? onJumpToSource;

  @override
  State<DoctorPage> createState() => _DoctorPageState();
}

enum _SortMode { priority, severity, category, file }

class _DoctorPageState extends State<DoctorPage> {
  bool _loadingProfiles = true;
  bool _running = false;
  String? _error;
  DoctorProfilesBundle? _profiles;
  String _selectedProfile = 'default';
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
      _loadingProfiles = true;
      _error = null;
    });
    try {
      final bundle = await widget.gateway.getDoctorProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = bundle;
        _loadingProfiles = false;
        if (bundle.profiles.isNotEmpty) {
          _selectedProfile = bundle.profiles
              .firstWhere(
                (p) => p.id == 'default',
                orElse: () => bundle.profiles.first,
              )
              .id;
        }
      });
      await _runDoctor();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfiles = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runDoctor() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final report = await widget.gateway.runDoctor(profile: _selectedProfile);
      if (!mounted) return;
      setState(() {
        _report = report;
        _running = false;
        _expandedFindingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
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
            selectedProfile: _selectedProfile,
            profiles: _profiles?.profiles ?? const [],
            running: _running,
            onProfileChanged: (id) {
              setState(() => _selectedProfile = id);
            },
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
            child: _loadingProfiles || (_running && _report == null)
                ? const Center(child: CircularProgressIndicator())
                : _report == null
                ? EmptyState(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Run Robot Doctor',
                    message:
                        'Analyze project health — prioritized findings, not a dump of every warning.',
                    actionLabel: 'Run Doctor',
                    onAction: () => unawaited(_runDoctor()),
                  )
                : _visibleFindings.isEmpty
                ? EmptyState(
                    icon: Icons.verified_outlined,
                    title: _report!.findings.isEmpty
                        ? 'Looking healthy'
                        : 'No matching findings',
                    message: _report!.findings.isEmpty
                        ? 'Doctor found nothing for this profile. Try Full to include execution knowledge.'
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
  const _Header({
    required this.selectedProfile,
    required this.profiles,
    required this.running,
    required this.onProfileChanged,
    required this.onRun,
  });

  final String selectedProfile;
  final List<DoctorProfileInfo> profiles;
  final bool running;
  final ValueChanged<String> onProfileChanged;
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
                  'Project Health Center — what should you fix first?',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (profiles.isNotEmpty) ...[
            SizedBox(
              height: 32,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: profiles.any((p) => p.id == selectedProfile)
                      ? selectedProfile
                      : profiles.first.id,
                  items: profiles
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.title,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: running
                      ? null
                      : (v) {
                          if (v != null) onProfileChanged(v);
                        },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          FilledButton.icon(
            onPressed: onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(running ? 'Running…' : 'Run Doctor'),
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
    final exec = report.executionSnapshot;
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
            label: 'Critical',
            value: '${s.criticalIssues}',
            emphasize: s.criticalIssues > 0,
          ),
          _StatChip(label: 'Errors', value: '${s.bySeverity['error'] ?? 0}'),
          _StatChip(
            label: 'Warnings',
            value: '${s.bySeverity['warning'] ?? 0}',
          ),
          _StatChip(
            label: 'Graph',
            value: report.graphVersion.isEmpty
                ? '—'
                : report.graphVersion.length > 8
                ? report.graphVersion.substring(0, 8)
                : report.graphVersion,
          ),
          if (exec != null)
            _StatChip(label: 'Linked runs', value: '${exec.linkedRuns}'),
          if (trend != null)
            _StatChip(
              label: 'Trend',
              value: trend.deltaTotal == 0
                  ? 'unchanged'
                  : trend.deltaTotal < 0
                  ? '${trend.deltaTotal} vs last'
                  : '+${trend.deltaTotal} vs last',
              emphasize: trend.improved,
              positive: trend.improved,
            ),
          ...s.byCategory.entries.map(
            (e) => _StatChip(label: _categoryLabel(e.key), value: '${e.value}'),
          ),
        ],
      ),
    );
  }
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
          onChanged: (v) {
            if (v != null) onSort(v);
          },
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
                    _ConfidenceBadge(confidence: finding.confidence),
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
                  Text(
                    'Why is this reported?',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    finding.rationale.isEmpty
                        ? 'No additional rationale from the provider.'
                        : finding.rationale,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (finding.filePath.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: onJump == null
                              ? null
                              : () => onJump!(
                                  finding.filePath,
                                  line: finding.line,
                                  column: finding.column,
                                ),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Jump to source'),
                        ),
                    ],
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

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});

  final String confidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.palette.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(
          color: context.palette.accentMuted.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        confidence,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: context.palette.accent),
      ),
    );
  }
}

String _categoryLabel(String category) {
  return switch (category) {
    'correctness' => 'Correctness',
    'maintainability' => 'Maintainability',
    'performance' => 'Performance',
    'dependencies' => 'Dependencies',
    'execution' => 'Execution',
    'style' => 'Style',
    _ => category,
  };
}

int _categoryRank(String category) {
  const order = [
    'correctness',
    'dependencies',
    'execution',
    'performance',
    'maintainability',
    'style',
  ];
  final i = order.indexOf(category);
  return i < 0 ? 99 : i;
}
