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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              sliver: SliverToBoxAdapter(
                child: _FilesPanel(rows: files, onOpenFile: onOpenFile),
              ),
            ),
          ],
        );
      },
    );
  }
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
      ('Keywords', '${data.countFor('keyword')}', null),
      ('Test cases', '${data.countFor('test_case')}', null),
      ('Variables', '${data.countFor('variable')}', null),
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
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.1,
              color: valueColor ?? context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.borderSubtle),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _CompositionPanel extends StatelessWidget {
  const _CompositionPanel({required this.data, this.onRebuildIndex});

  final InsightsInfo data;
  final VoidCallback? onRebuildIndex;

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
          ],
        ),
      );
    }

    final entries = _kinds
        .where((k) => data.countFor(k.$1) > 0)
        .map((k) => (k.$1, k.$2, data.countFor(k.$1)))
        .toList();
    final maxCount = entries.fold<int>(0, (m, e) => e.$3 > m ? e.$3 : m);
    final total = entries.fold<int>(0, (s, e) => s + e.$3);

    return _Panel(
      title: 'Composition',
      trailing: Text(
        '$total symbols',
        style: TextStyle(fontSize: 11, color: context.palette.textMuted),
      ),
      child: Column(
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
        ],
      ),
    );
  }
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
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: context.palette.textPrimary,
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
                _OutcomeStatRow(runs: runs),
                const SizedBox(height: AppSpacing.md),
                _OutcomeShareBar(runs: runs),
                if (data.recentRuns.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel('Recent'),
                  const SizedBox(height: AppSpacing.sm),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                      border: Border.all(color: context.palette.borderSubtle),
                    ),
                    child: SizedBox(
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: _OutcomeSparkline(runs: data.recentRuns),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _LastRunLine(run: data.recentRuns.first),
                ],
                if (failing.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel('Top failures'),
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

class _OutcomeStatRow extends StatelessWidget {
  const _OutcomeStatRow({required this.runs});

  final InsightsRunTotals runs;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, int, Color)>[
      ('Pass', runs.passed, context.palette.success),
      ('Fail', runs.failed, context.palette.error),
      ('Cancel', runs.cancelled, context.palette.warning),
      ('Abort', runs.aborted, context.palette.textMuted),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              color: context.palette.borderSubtle,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cells[i].$1,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${cells[i].$2}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: cells[i].$2 > 0
                        ? cells[i].$3
                        : context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OutcomeShareBar extends StatelessWidget {
  const _OutcomeShareBar({required this.runs});

  final InsightsRunTotals runs;

  @override
  Widget build(BuildContext context) {
    final segments = <(int, Color, String)>[
      (runs.passed, context.palette.success, 'Pass'),
      (runs.failed, context.palette.error, 'Fail'),
      (runs.cancelled, context.palette.warning, 'Cancel'),
      (runs.aborted, context.palette.textMuted, 'Abort'),
    ].where((s) => s.$1 > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xs),
          child: SizedBox(
            height: 10,
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
        ),
        if (runs.skippedTests > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${runs.skippedTests} skipped tests',
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ],
    );
  }
}

class _LastRunLine extends StatelessWidget {
  const _LastRunLine({required this.run});

  final InsightsRecentRun run;

  @override
  Widget build(BuildContext context) {
    final name = run.suite.replaceAll('\\', '/').split('/').last;
    final outcome = run.outcome.isEmpty ? run.status.label : run.outcome;
    final color = switch (outcome.toUpperCase()) {
      'PASS' => context.palette.success,
      'FAIL' => context.palette.error,
      'CANCELLED' => context.palette.warning,
      'ABORTED' => context.palette.textMuted,
      _ => context.palette.textSecondary,
    };
    return Row(
      children: [
        Text(
          'Last',
          style: TextStyle(fontSize: 11, color: context.palette.textMuted),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
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
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ],
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
              vertical: AppSpacing.xs,
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
                Text(
                  '${widget.file.failed}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.palette.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ' / ${widget.file.runs}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textMuted,
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

class _FilesPanel extends StatelessWidget {
  const _FilesPanel({required this.rows, this.onOpenFile});

  final List<_MergedFileRow> rows;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Text('Files', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.borderSubtle),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No file-level data yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            _FileTable(rows: rows, onOpenFile: onOpenFile),
        ],
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

class _FileTable extends StatelessWidget {
  const _FileTable({required this.rows, this.onOpenFile});

  final List<_MergedFileRow> rows;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ColoredBox(
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
        ),
        for (var i = 0; i < rows.length; i++)
          _FileDataRow(
            row: rows[i],
            striped: i.isOdd,
            onOpen: onOpenFile == null
                ? null
                : () => onOpenFile!(rows[i].filePath),
          ),
      ],
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

class _OutcomeSparkline extends StatelessWidget {
  const _OutcomeSparkline({required this.runs});

  final List<InsightsRecentRun> runs;

  @override
  Widget build(BuildContext context) {
    final ordered = runs.reversed.toList();
    return CustomPaint(
      painter: _SparklinePainter(
        outcomes: ordered.map((r) => r.outcome).toList(),
        pass: context.palette.success,
        fail: context.palette.error,
        cancel: context.palette.warning,
        abort: context.palette.textMuted,
        track: context.palette.surfaceElevated,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.outcomes,
    required this.pass,
    required this.fail,
    required this.cancel,
    required this.abort,
    required this.track,
  });

  final List<String> outcomes;
  final Color pass;
  final Color fail;
  final Color cancel;
  final Color abort;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (outcomes.isEmpty) return;
    final n = outcomes.length;
    final slot = size.width / n;
    final barW = (slot * 0.58).clamp(3.0, 10.0);
    final barH = size.height;
    for (var i = 0; i < n; i++) {
      final outcome = outcomes[i];
      final color = switch (outcome) {
        'PASS' => pass,
        'FAIL' => fail,
        'CANCELLED' => cancel,
        'ABORTED' => abort,
        _ => track,
      };
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, barW, barH),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.outcomes != outcomes;
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
  for (final run in data.runFiles) {
    final key = _matchRunToFile(run.filePath, map.keys);
    if (key == null) continue;
    final existing = map[key]!;
    map[key] = _MergedFileRow(
      filePath: existing.filePath,
      counts: existing.counts,
      runs: run.runs,
      passed: run.passed,
      failed: run.failed,
      cancelled: run.cancelled,
      aborted: run.aborted,
      lastOutcome: run.lastOutcome,
      lastStartedAt: run.lastStartedAt,
    );
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

String? _matchRunToFile(String suite, Iterable<String> files) {
  if (!_looksLikeSourceFile(suite)) return null;
  if (files.contains(suite)) return suite;
  final suiteName = suite.replaceAll('\\', '/').split('/').last;
  for (final file in files) {
    final name = file.replaceAll('\\', '/').split('/').last;
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
