import 'package:flutter/material.dart';

import '../../core/gateway/models/insights_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';

/// Project Insights — dense health + composition canvas (IDE chrome).
class InsightsPage extends StatelessWidget {
  const InsightsPage({
    super.key,
    required this.insights,
    required this.isLoading,
    this.onRefresh,
    this.onRebuildIndex,
    this.onOpenFile,
    this.onOpenReports,
  });

  final InsightsInfo? insights;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final VoidCallback? onRebuildIndex;
  final ValueChanged<String>? onOpenFile;
  final VoidCallback? onOpenReports;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onRebuildIndex: onRebuildIndex, onRefresh: onRefresh),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading && insights == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final data = insights;
    if (data == null) {
      return EmptyState(
        icon: Icons.insights_outlined,
        title: 'Insights unavailable',
        message:
            'Open a project and refresh to load composition and run health.',
        actionLabel: onRefresh == null ? null : 'Refresh',
        onAction: onRefresh,
      );
    }

    final files = _mergeFileRows(data);
    final failing = data.runFiles.where((f) => f.failed > 0).take(5).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return CustomScrollView(
          cacheExtent: 320,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              sliver: SliverToBoxAdapter(child: _HeadlineStrip(data: data)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverToBoxAdapter(
                child: wide
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _CompositionPanel(
                                data: data,
                                onRebuildIndex: onRebuildIndex,
                                onOpenFile: onOpenFile,
                                expandBody: true,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _RunHealthPanel(
                                data: data,
                                failing: failing,
                                onOpenReports: onOpenReports,
                                onOpenFile: onOpenFile,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          _CompositionPanel(
                            data: data,
                            onRebuildIndex: onRebuildIndex,
                            onOpenFile: onOpenFile,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _RunHealthPanel(
                            data: data,
                            failing: failing,
                            onOpenReports: onOpenReports,
                            onOpenFile: onOpenFile,
                          ),
                        ],
                      ),
              ),
            ),
            // Lazy file rows — never mount 10k Table rows in one box.
            ..._filesSlivers(
              context: context,
              rows: files,
              onOpenFile: onOpenFile,
            ),
          ],
        );
      },
    );
  }
}

List<Widget> _filesSlivers({
  required BuildContext context,
  required List<_MergedFileRow> rows,
  required ValueChanged<String>? onOpenFile,
}) {
  final palette = context.palette;
  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: palette.border),
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Text(
                      'Files',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _formatCount(rows.length),
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Divider(height: 1, color: palette.borderSubtle),
            ),
            if (rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No file-level data yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else ...[
              const SliverToBoxAdapter(child: _FileTableHeader()),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final row = rows[index];
                    return _FileDataRow(
                      row: row,
                      striped: index.isOdd,
                      onOpen: onOpenFile == null
                          ? null
                          : () => onOpenFile(row.filePath),
                    );
                  },
                  childCount: rows.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  ];
}

class _Header extends StatelessWidget {
  const _Header({this.onRebuildIndex, this.onRefresh});

  final VoidCallback? onRebuildIndex;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insights',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  'Composition and run health for this project.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onRebuildIndex != null)
            OutlinedButton(
              onPressed: onRebuildIndex,
              child: const Text('Rebuild Index'),
            ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

/// Single dense strip — the numbers you glance at first.
class _HeadlineStrip extends StatelessWidget {
  const _HeadlineStrip({required this.data});

  final InsightsInfo data;

  @override
  Widget build(BuildContext context) {
    final runs = data.runs;
    final items = <(String, String, Color?)>[
      (
        'Pass rate',
        data.hasRuns ? runs.passRateLabel : '—',
        data.hasRuns ? context.palette.success : null,
      ),
      ('Runs', data.hasRuns ? '${runs.total}' : '0', null),
      ('Failed', data.hasRuns ? '${runs.failed}' : '0', context.palette.error),
      ('Avg duration', data.hasRuns ? runs.averageDurationLabel : '—', null),
      ('Keywords', _formatCount(data.countFor('keyword')), null),
      ('Test cases', _formatCount(data.countFor('test_case')), null),
      ('Variables', _formatCount(data.countFor('variable')), null),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(
          top: BorderSide(color: context.palette.border),
          bottom: BorderSide(color: context.palette.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: context.palette.borderSubtle,
                  ),
                _HeadlineCell(
                  label: items[i].$1,
                  value: items[i].$2,
                  valueColor: items[i].$3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadlineCell extends StatelessWidget {
  const _HeadlineCell({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: context.palette.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: valueColor ?? context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.trailing,
    this.fillBody = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Stretch body when the panel is in a tall IntrinsicHeight row.
  final bool fillBody;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: const EdgeInsets.all(12), child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null)
                  Flexible(
                    child: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      child: trailing!,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.borderSubtle),
          if (fillBody) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class _CompositionPanel extends StatelessWidget {
  const _CompositionPanel({
    required this.data,
    this.onRebuildIndex,
    this.onOpenFile,
    this.expandBody = false,
  });

  final InsightsInfo data;
  final VoidCallback? onRebuildIndex;
  final ValueChanged<String>? onOpenFile;

  /// Stretch Focus card to match Run health height in wide layout.
  final bool expandBody;

  static const _kinds = <(String, String)>[
    ('keyword', 'Keywords'),
    ('test_case', 'Test cases'),
    ('test_suite', 'Suites'),
    ('resource', 'Resources'),
    ('library', 'Libraries'),
    ('variable', 'Variables'),
    ('file', 'Files'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!data.hasComposition) {
      return _Panel(
        title: 'Composition',
        fillBody: expandBody,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No indexed symbols yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRebuildIndex != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onRebuildIndex,
                child: const Text('Rebuild Index'),
              ),
            ],
            if (expandBody) const Spacer(),
          ],
        ),
      );
    }

    final entries = _kinds
        .where((k) => data.countFor(k.$1) > 0)
        .map((k) => (k.$1, k.$2, data.countFor(k.$1)))
        .toList();
    final maxCount = entries.fold<int>(0, (m, e) => e.$3 > m ? e.$3 : m);
    // Content definitions only — file/suite rows are inventory, not "symbols".
    final contentTotal = entries
        .where((e) => e.$1 != 'file' && e.$1 != 'test_suite')
        .fold<int>(0, (s, e) => s + e.$3);

    return _Panel(
      title: 'Composition',
      fillBody: expandBody,
      trailing: Text(
        contentTotal > 0
            ? '${_formatCount(contentTotal)} indexed · ${_formatCount(data.countFor('file'))} files'
            : '${_formatCount(data.countFor('file'))} files',
        style: TextStyle(fontSize: 11, color: context.palette.textMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BarRow(
                label: entry.$2,
                value: entry.$3,
                max: maxCount,
                color: _kindColor(context, entry.$1),
              ),
            ),
          if (expandBody)
            const Spacer()
          else
            const SizedBox(height: AppSpacing.lg),
          _CompositionFocusCard(data: data, onOpenFile: onOpenFile),
        ],
      ),
    );
  }
}

/// Densest files + quick density ratios — fills leftover Composition height.
class _CompositionFocusCard extends StatelessWidget {
  const _CompositionFocusCard({required this.data, this.onOpenFile});

  final InsightsInfo data;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final densest = _densestFiles(data.compositionFiles, limit: 4);
    final keywords = data.countFor('keyword');
    final tests = data.countFor('test_case');
    final files = data.countFor('file');
    final resources = data.countFor('resource');
    final libraries = data.countFor('library');
    const skipKinds = {'file', 'test_suite', 'tag', 'setting', 'documentation'};
    final contentTotal = data.composition.entries
        .where((e) => !skipKinds.contains(e.key))
        .fold<int>(0, (s, e) => s + e.value);
    final perFile = files > 0 ? (contentTotal / files) : 0.0;
    final kwPerTest = tests > 0 ? keywords / tests : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'FOCUS',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
                Text(
                  _indexStateLabel(data.indexState),
                  style: TextStyle(
                    fontSize: 10,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _FocusChip(
                  label: kwPerTest == null
                      ? 'KW / test —'
                      : 'KW / test ${kwPerTest.toStringAsFixed(1)}',
                ),
                _FocusChip(
                  label: perFile <= 0
                      ? 'Symbols / file —'
                      : 'Symbols / file ${perFile.toStringAsFixed(1)}',
                ),
                _FocusChip(label: 'Resources $resources'),
                _FocusChip(label: 'Libraries $libraries'),
              ],
            ),
            if (densest.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'DENSEST FILES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final item in densest)
                _DenseFileRow(
                  filePath: item.$1,
                  total: item.$2,
                  max: densest.first.$2,
                  onOpen: onOpenFile == null
                      ? null
                      : () => onOpenFile!(item.$1),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _indexStateLabel(String state) {
    final s = state.trim().toLowerCase();
    if (s.isEmpty || s == 'idle') return 'Index idle';
    if (s == 'ready') return 'Index ready';
    if (s == 'indexing' || s == 'busy') return 'Indexing…';
    return 'Index $state';
  }
}

class _FocusChip extends StatelessWidget {
  const _FocusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: context.palette.textSecondary),
      ),
    );
  }
}

class _DenseFileRow extends StatefulWidget {
  const _DenseFileRow({
    required this.filePath,
    required this.total,
    required this.max,
    this.onOpen,
  });

  final String filePath;
  final int total;
  final int max;
  final VoidCallback? onOpen;

  @override
  State<_DenseFileRow> createState() => _DenseFileRowState();
}

class _DenseFileRowState extends State<_DenseFileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.filePath.replaceAll('\\', '/').split('/').last;
    final fraction = widget.max <= 0 ? 0.0 : widget.total / widget.max;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? context.palette.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(AppRadii.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: context.palette.surface),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: fraction.clamp(0.04, 1.0),
                            child: ColoredBox(color: context.palette.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 48,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatCount(widget.total),
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<(String, int)> _densestFiles(
  List<InsightsFileComposition> files, {
  int limit = 4,
}) {
  const skipKinds = {'file', 'test_suite', 'tag', 'setting', 'documentation'};
  final scored = <(String, int)>[];
  for (final file in files) {
    if (!_looksLikeSourceFile(file.filePath)) continue;
    final total = file.counts.entries
        .where((e) => !skipKinds.contains(e.key))
        .fold<int>(0, (s, e) => s + e.value);
    if (total <= 0) continue;
    scored.add((file.filePath, total));
  }
  scored.sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    if (byCount != 0) return byCount;
    return a.$1.compareTo(b.$1);
  });
  return scored.take(limit).toList();
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : value / max;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.xs),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: context.palette.surfaceElevated),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction.clamp(0.02, 1.0),
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 76,
          child: Tooltip(
            message: '$value',
            waitDuration: const Duration(milliseconds: 400),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _formatCount(value),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RunHealthPanel extends StatelessWidget {
  const _RunHealthPanel({
    required this.data,
    required this.failing,
    this.onOpenReports,
    this.onOpenFile,
  });

  final InsightsInfo data;
  final List<InsightsFileRuns> failing;
  final VoidCallback? onOpenReports;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final runs = data.runs;
    final recent = data.recentRuns;
    final chronological = recent.reversed.toList();
    final streak = _outcomeStreak(recent);
    final maxDuration = chronological
        .map((r) => r.durationMs ?? 0)
        .fold<int>(0, (m, v) => v > m ? v : m);
    // Last run only — summing test counts across runs double-counts suites.
    final last = recent.isEmpty ? null : recent.first;
    final testsPassed = last?.passed ?? 0;
    final testsFailed = last?.failed ?? 0;

    return _Panel(
      title: 'Run health',
      trailing: onOpenReports == null
          ? null
          : TextButton(
              onPressed: onOpenReports,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('View in Reports'),
            ),
      child: !data.hasRuns
          ? Text(
              'No runs yet. Execute a suite to unlock pass/fail trends and per-file health.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HealthMetricGrid(
                  runs: runs,
                  testsPassed: testsPassed,
                  testsFailed: testsFailed,
                  streak: streak,
                ),
                const SizedBox(height: AppSpacing.md),
                _OutcomeShareBar(runs: runs),
                if (chronological.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Expanded(child: _SectionLabel('Duration trend')),
                      Text(
                        'last ${chronological.length} · oldest → newest',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                      border: Border.all(color: context.palette.borderSubtle),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 88,
                            child: _DurationTrendChart(runs: chronological),
                          ),
                          if (maxDuration > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Peak ${_formatDurationMs(maxDuration)} · avg ${runs.averageDurationLabel}',
                              style: TextStyle(
                                fontSize: 10,
                                color: context.palette.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Last run'),
                  const SizedBox(height: AppSpacing.sm),
                  _LastRunCard(run: recent.first),
                ],
                if (failing.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionLabel('Top failures'),
                  const SizedBox(height: AppSpacing.xs),
                  for (final file in failing)
                    _FailingFileRow(
                      file: file,
                      onOpen: onOpenFile == null
                          ? null
                          : () => onOpenFile!(file.filePath),
                    ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
        color: context.palette.textMuted,
      ),
    );
  }
}

class _HealthMetricGrid extends StatelessWidget {
  const _HealthMetricGrid({
    required this.runs,
    required this.testsPassed,
    required this.testsFailed,
    required this.streak,
  });

  final InsightsRunTotals runs;
  final int testsPassed;
  final int testsFailed;
  final _RunStreak streak;

  @override
  Widget build(BuildContext context) {
    final passColor = (runs.passRate ?? 0) >= 80
        ? context.palette.success
        : (runs.passRate ?? 0) >= 50
        ? context.palette.warning
        : context.palette.error;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Pass rate',
                value: runs.passRateLabel,
                valueColor: passColor,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                label: 'Avg duration',
                value: runs.averageDurationLabel,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(label: 'Runs', value: '${runs.total}'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Pass',
                value: '${runs.passed}',
                valueColor: runs.passed > 0 ? context.palette.success : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                label: 'Fail',
                value: '${runs.failed}',
                valueColor: runs.failed > 0 ? context.palette.error : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                label: streak.label,
                value: streak.count == 0 ? '—' : '${streak.count}',
                valueColor: streak.count == 0
                    ? null
                    : streak.isPass
                    ? context.palette.success
                    : context.palette.error,
              ),
            ),
          ],
        ),
        if (testsPassed + testsFailed + runs.skippedTests > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _testsSummary(
              testsPassed: testsPassed,
              testsFailed: testsFailed,
              skipped: runs.skippedTests,
              cancelled: runs.cancelled,
              aborted: runs.aborted,
            ),
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ],
    );
  }

  static String _testsSummary({
    required int testsPassed,
    required int testsFailed,
    required int skipped,
    required int cancelled,
    required int aborted,
  }) {
    final parts = <String>[];
    if (testsPassed + testsFailed > 0) {
      parts.add('$testsPassed pass / $testsFailed fail tests (last run)');
    }
    if (skipped > 0) parts.add('$skipped skipped');
    if (cancelled > 0) parts.add('$cancelled cancelled');
    if (aborted > 0) parts.add('$aborted aborted');
    return parts.join(' · ');
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.palette.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.15,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: valueColor ?? context.palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeShareBar extends StatelessWidget {
  const _OutcomeShareBar({required this.runs});

  final InsightsRunTotals runs;

  @override
  Widget build(BuildContext context) {
    final segments = <(int, Color)>[
      (runs.passed, context.palette.success),
      (runs.failed, context.palette.error),
      (runs.cancelled, context.palette.warning),
      (runs.aborted, context.palette.textMuted),
    ].where((s) => s.$1 > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: SizedBox(
        height: 6,
        child: segments.isEmpty
            ? ColoredBox(color: context.palette.surfaceElevated)
            : Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      flex: segment.$1,
                      child: ColoredBox(color: segment.$2),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LastRunCard extends StatelessWidget {
  const _LastRunCard({required this.run});

  final InsightsRecentRun run;

  @override
  Widget build(BuildContext context) {
    final name = run.suite.replaceAll('\\', '/').split('/').last;
    final outcome = run.outcome.isEmpty ? run.status.label : run.outcome;
    final color = _outcomeColor(context, outcome);
    final tests = <String>[];
    if (run.passed != null) tests.add('${run.passed}p');
    if (run.failed != null) tests.add('${run.failed}f');
    if ((run.skipped ?? 0) > 0) tests.add('${run.skipped}s');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              outcome,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                name.isEmpty ? run.id : name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            if (run.durationMs != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                _formatDurationMs(run.durationMs!),
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: context.palette.textSecondary,
                ),
              ),
            ],
            if (tests.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                tests.join(' '),
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: context.palette.textMuted,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            Text(
              _relativeTime(run.startedAt),
              style: TextStyle(fontSize: 11, color: context.palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailingFileRow extends StatefulWidget {
  const _FailingFileRow({required this.file, this.onOpen});

  final InsightsFileRuns file;
  final VoidCallback? onOpen;

  @override
  State<_FailingFileRow> createState() => _FailingFileRowState();
}

class _FailingFileRowState extends State<_FailingFileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.file.filePath.replaceAll('\\', '/').split('/').last;
    final rate = widget.file.runs <= 0
        ? 0.0
        : widget.file.failed / widget.file.runs;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? context.palette.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(AppRadii.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      children: [
                        ColoredBox(
                          color: context.palette.surfaceElevated,
                          child: const SizedBox.expand(),
                        ),
                        FractionallySizedBox(
                          widthFactor: rate.clamp(0.0, 1.0),
                          child: ColoredBox(color: context.palette.error),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${widget.file.failed}/${widget.file.runs}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.palette.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared column widths so header and rows stay on one grid.
abstract final class _FileCols {
  static const double pad = 12;

  /// File takes a modest share; metric columns split the rest evenly so
  /// nothing collapses into a right-hand clump with a dead gap in the middle.
  static Map<int, TableColumnWidth> get widths => {
    0: const FlexColumnWidth(2.4),
    1: const FlexColumnWidth(1),
    2: const FlexColumnWidth(1),
    3: const FlexColumnWidth(1),
    4: const FlexColumnWidth(1),
    5: const FlexColumnWidth(1),
    6: const FlexColumnWidth(1),
    7: const FlexColumnWidth(1),
    8: const FlexColumnWidth(1),
    9: const FlexColumnWidth(1.2),
  };

  static const headers = [
    'File',
    'KW',
    'TC',
    'Var',
    'Runs',
    'Pass',
    'Fail',
    'Cancel',
    'Abort',
    'Last',
  ];
}

class _FileTableHeader extends StatelessWidget {
  const _FileTableHeader();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.surfaceElevated,
      child: Table(
        columnWidths: _FileCols.widths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (var i = 0; i < _FileCols.headers.length; i++)
                _HeaderCell(
                  label: _FileCols.headers[i],
                  align: i == 0 ? Alignment.centerLeft : Alignment.center,
                  padLeft: i == 0 ? _FileCols.pad : 2,
                  padRight: i == _FileCols.headers.length - 1
                      ? _FileCols.pad
                      : 2,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.align,
    required this.padLeft,
    required this.padRight,
  });

  final String label;
  final Alignment align;
  final double padLeft;
  final double padRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padLeft, 7, padRight, 7),
      child: Align(
        alignment: align,
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w600,
            color: context.palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _FileDataRow extends StatefulWidget {
  const _FileDataRow({required this.row, required this.striped, this.onOpen});

  final _MergedFileRow row;
  final bool striped;
  final VoidCallback? onOpen;

  @override
  State<_FileDataRow> createState() => _FileDataRowState();
}

class _FileDataRowState extends State<_FileDataRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final base = widget.striped
        ? context.palette.surfaceElevated.withValues(alpha: 0.35)
        : Colors.transparent;
    final bg = _hover ? context.palette.surfaceHover : base;

    Widget numCell(String text, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Align(
          alignment: Alignment.center,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
              color: color ?? context.palette.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onOpen,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.palette.borderSubtle),
              ),
            ),
            child: Table(
              columnWidths: _FileCols.widths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _FileCols.pad,
                        7,
                        4,
                        7,
                      ),
                      child: Text(
                        row.shortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                    numCell('${row.counts['keyword'] ?? 0}'),
                    numCell('${row.counts['test_case'] ?? 0}'),
                    numCell('${row.counts['variable'] ?? 0}'),
                    numCell('${row.runs}'),
                    numCell('${row.passed}', color: context.palette.success),
                    numCell(
                      '${row.failed}',
                      color: row.failed > 0 ? context.palette.error : null,
                    ),
                    numCell('${row.cancelled}'),
                    numCell('${row.aborted}'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        2,
                        5,
                        _FileCols.pad,
                        5,
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: row.lastOutcome == null
                            ? Text(
                                '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.textMuted,
                                ),
                              )
                            : StatusBadge(label: row.lastOutcome!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationTrendChart extends StatelessWidget {
  const _DurationTrendChart({required this.runs});

  final List<InsightsRecentRun> runs;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      painter: _DurationTrendPainter(
        runs: runs,
        pass: p.success,
        fail: p.error,
        cancel: p.warning,
        abort: p.textMuted,
        grid: p.borderSubtle,
        label: p.textMuted,
        fallback: p.accent,
      ),
      isComplex: true,
      willChange: false,
      child: const SizedBox.expand(),
    );
  }
}

class _DurationTrendPainter extends CustomPainter {
  _DurationTrendPainter({
    required this.runs,
    required this.pass,
    required this.fail,
    required this.cancel,
    required this.abort,
    required this.grid,
    required this.label,
    required this.fallback,
  });

  final List<InsightsRecentRun> runs;
  final Color pass;
  final Color fail;
  final Color cancel;
  final Color abort;
  final Color grid;
  final Color label;
  final Color fallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (runs.isEmpty) return;

    const leftGutter = 34.0;
    final chartW = size.width - leftGutter;
    final chartH = size.height;
    final maxMs = runs
        .map((r) => r.durationMs ?? 0)
        .fold<int>(0, (m, v) => v > m ? v : m);
    final hasDuration = maxMs > 0;
    final scaleMax = hasDuration ? maxMs.toDouble() : 1.0;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final t in [0.0, 0.5, 1.0]) {
      final y = chartH - t * chartH;
      canvas.drawLine(Offset(leftGutter, y), Offset(size.width, y), gridPaint);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawY(String text, double y) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(fontSize: 9, color: label),
      );
      tp.layout(maxWidth: leftGutter - 4);
      tp.paint(
        canvas,
        Offset(0, (y - tp.height / 2).clamp(0.0, chartH - tp.height)),
      );
    }

    if (hasDuration) {
      drawY(_formatDurationMs(maxMs), 0);
      drawY(_formatDurationMs(maxMs ~/ 2), chartH / 2);
      drawY('0', chartH);
    } else {
      drawY('n/a', chartH / 2);
    }

    final n = runs.length;
    final slot = chartW / n;
    final barW = (slot * 0.62).clamp(3.0, 14.0);
    final linePoints = <Offset>[];

    for (var i = 0; i < n; i++) {
      final run = runs[i];
      final ms = run.durationMs;
      final frac = hasDuration
          ? ((ms ?? scaleMax * 0.18) / scaleMax).clamp(0.08, 1.0)
          : 0.55;
      final barH = frac * chartH;
      final x = leftGutter + i * slot + (slot - barW) / 2;
      final y = chartH - barH;
      final color = switch (run.outcome.toUpperCase()) {
        'PASS' => pass,
        'FAIL' => fail,
        'CANCELLED' => cancel,
        'ABORTED' => abort,
        _ => fallback,
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          const Radius.circular(2),
        ),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      linePoints.add(Offset(x + barW / 2, y));
    }

    if (hasDuration && linePoints.length >= 2) {
      final path = Path()..moveTo(linePoints.first.dx, linePoints.first.dy);
      for (var i = 1; i < linePoints.length; i++) {
        path.lineTo(linePoints[i].dx, linePoints[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = fallback.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
      for (final pt in linePoints) {
        canvas.drawCircle(pt, 2.2, Paint()..color = fallback);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DurationTrendPainter oldDelegate) =>
      oldDelegate.runs != runs;
}

class _RunStreak {
  const _RunStreak({required this.count, required this.isPass});

  final int count;
  final bool isPass;

  String get label {
    if (count <= 0) return 'Streak';
    return isPass ? 'Pass streak' : 'Fail streak';
  }
}

_RunStreak _outcomeStreak(List<InsightsRecentRun> recentNewestFirst) {
  if (recentNewestFirst.isEmpty) {
    return const _RunStreak(count: 0, isPass: true);
  }
  final first = recentNewestFirst.first.outcome.toUpperCase();
  final isPass = first == 'PASS';
  if (first != 'PASS' && first != 'FAIL') {
    return const _RunStreak(count: 0, isPass: true);
  }
  var count = 0;
  for (final run in recentNewestFirst) {
    final o = run.outcome.toUpperCase();
    if (o != first) break;
    count++;
  }
  return _RunStreak(count: count, isPass: isPass);
}

Color _outcomeColor(BuildContext context, String outcome) {
  return switch (outcome.toUpperCase()) {
    'PASS' => context.palette.success,
    'FAIL' => context.palette.error,
    'CANCELLED' => context.palette.warning,
    'ABORTED' => context.palette.textMuted,
    _ => context.palette.textSecondary,
  };
}

String _formatDurationMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000;
  if (seconds < 60) {
    return seconds >= 10
        ? '${seconds.toStringAsFixed(0)}s'
        : '${seconds.toStringAsFixed(1)}s';
  }
  final minutes = seconds ~/ 60;
  final rem = (seconds % 60).round();
  return rem == 0 ? '${minutes}m' : '${minutes}m ${rem}s';
}

String _relativeTime(DateTime at) {
  final local = at.toLocal();
  final delta = DateTime.now().difference(local);
  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return '${local.month}/${local.day}';
}

class _MergedFileRow {
  _MergedFileRow({
    required this.filePath,
    required this.counts,
    this.runs = 0,
    this.passed = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.aborted = 0,
    this.lastOutcome,
    this.lastStartedAt,
  });

  final String filePath;
  final Map<String, int> counts;
  final int runs;
  final int passed;
  final int failed;
  final int cancelled;
  final int aborted;
  final String? lastOutcome;
  final DateTime? lastStartedAt;

  String get shortName {
    final parts = filePath.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? filePath : parts.last;
  }
}

List<_MergedFileRow> _mergeFileRows(InsightsInfo data) {
  // Composition owns the file list. Run-only labels (e.g. "Project: Foo")
  // must not invent rows.
  final map = <String, _MergedFileRow>{};
  for (final file in data.compositionFiles) {
    if (!_looksLikeSourceFile(file.filePath)) continue;
    map[file.filePath] = _MergedFileRow(
      filePath: file.filePath,
      counts: Map<String, int>.from(file.counts),
    );
  }

  void applyRun({
    required String suite,
    required int runs,
    required int passed,
    required int failed,
    required int cancelled,
    required int aborted,
    String? lastOutcome,
    DateTime? lastStartedAt,
  }) {
    final key = _matchRunToFile(suite, map.keys);
    if (key == null) return;
    final existing = map[key]!;
    final newer =
        lastStartedAt != null &&
        (existing.lastStartedAt == null ||
            lastStartedAt.isAfter(existing.lastStartedAt!));
    map[key] = _MergedFileRow(
      filePath: existing.filePath,
      counts: existing.counts,
      runs: existing.runs + runs,
      passed: existing.passed + passed,
      failed: existing.failed + failed,
      cancelled: existing.cancelled + cancelled,
      aborted: existing.aborted + aborted,
      lastOutcome: newer ? lastOutcome : existing.lastOutcome,
      lastStartedAt: newer ? lastStartedAt : existing.lastStartedAt,
    );
  }

  for (final run in data.runFiles) {
    applyRun(
      suite: run.filePath,
      runs: run.runs,
      passed: run.passed,
      failed: run.failed,
      cancelled: run.cancelled,
      aborted: run.aborted,
      lastOutcome: run.lastOutcome,
      lastStartedAt: run.lastStartedAt,
    );
  }

  // Fallback: if aggregates missed a path, still stamp last recent file run.
  if (data.runFiles.isEmpty) {
    for (final recent in data.recentRuns) {
      final outcome = recent.outcome.toUpperCase();
      applyRun(
        suite: recent.suite,
        runs: 1,
        passed: outcome == 'PASS' ? 1 : 0,
        failed: outcome == 'FAIL' ? 1 : 0,
        cancelled: outcome == 'CANCELLED' ? 1 : 0,
        aborted: outcome == 'ABORTED' ? 1 : 0,
        lastOutcome: recent.outcome.isEmpty ? null : recent.outcome,
        lastStartedAt: recent.startedAt,
      );
    }
  }

  final rows = map.values.toList()
    ..sort((a, b) {
      final failCmp = b.failed.compareTo(a.failed);
      if (failCmp != 0) return failCmp;
      final runCmp = b.runs.compareTo(a.runs);
      if (runCmp != 0) return runCmp;
      return a.filePath.compareTo(b.filePath);
    });
  return rows;
}

bool _looksLikeSourceFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.robot') ||
      lower.endsWith('.resource') ||
      lower.endsWith('.py') ||
      lower.endsWith('.yaml') ||
      lower.endsWith('.yml');
}

/// Group thousands for dense IDE counts (keeps full precision, avoids wrap).
String _formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  if (value < 0) buffer.write('-');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String? _matchRunToFile(String suite, Iterable<String> files) {
  final cleaned = suite.trim();
  if (!_looksLikeSourceFile(cleaned)) return null;
  if (files.contains(cleaned)) return cleaned;
  final suiteName = cleaned.replaceAll('\\', '/').split('/').last.toLowerCase();
  for (final file in files) {
    final name = file.replaceAll('\\', '/').split('/').last.toLowerCase();
    if (name == suiteName) return file;
  }
  return null;
}

Color _kindColor(BuildContext context, String kind) {
  final p = context.palette;
  // One distinct hue per kind — avoid shade-only pairs (accent/accentMuted, grays).
  return switch (kind) {
    'keyword' => p.accent,
    'test_case' => p.success,
    'test_suite' => p.info,
    'resource' => p.warning,
    'library' => Color.lerp(p.warning, p.error, 0.55)!,
    'variable' => p.isDark ? const Color(0xFFC77DAB) : const Color(0xFF9A4F7A),
    'file' => p.isDark ? const Color(0xFF7B8FB0) : const Color(0xFF4A5F80),
    _ => p.border,
  };
}
