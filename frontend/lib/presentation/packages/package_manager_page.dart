import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/timed_loading_indicator.dart';

class PackageManagerPage extends StatelessWidget {
  const PackageManagerPage({
    super.key,
    required this.packages,
    required this.isLoading,
    required this.sort,
    required this.query,
    required this.selected,
    required this.robotInstalled,
    required this.hasActiveEnvironment,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onSearchPyPI,
    required this.onImportRequirements,
    required this.onExportRequirements,
    required this.onSelect,
    required this.onUpdate,
    required this.onUninstall,
    required this.onInstallRobot,
  });

  final List<PackageInfo> packages;
  final bool isLoading;
  final PackageSort sort;
  final String query;
  final PackageInfo? selected;
  final bool robotInstalled;
  final bool hasActiveEnvironment;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<PackageSort> onSortChanged;
  final VoidCallback onRefresh;
  final VoidCallback onSearchPyPI;
  final VoidCallback onImportRequirements;
  final VoidCallback onExportRequirements;
  final ValueChanged<PackageInfo> onSelect;
  final ValueChanged<PackageInfo> onUpdate;
  final ValueChanged<PackageInfo> onUninstall;
  final VoidCallback onInstallRobot;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Package Manager',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasActiveEnvironment
                            ? 'Manage packages in the active virtual environment.'
                            : 'Activate a Python environment to manage packages.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: hasActiveEnvironment ? onRefresh : null,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: hasActiveEnvironment ? onImportRequirements : null,
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Import requirements'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: hasActiveEnvironment ? onExportRequirements : null,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Export requirements'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: hasActiveEnvironment ? onSearchPyPI : null,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Search PyPI'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                if (!robotInstalled && hasActiveEnvironment)
                  TextButton(
                    onPressed: onInstallRobot,
                    child: const Text('Install Robot Framework'),
                  ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search installed',
                      isDense: true,
                    ),
                    onChanged: onQueryChanged,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                DropdownButton<PackageSort>(
                  value: sort,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.textPrimary,
                  ),
                  underline: const SizedBox.shrink(),
                  items: PackageSort.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          Expanded(
            child: !hasActiveEnvironment
                ? const EmptyState(
                    icon: Icons.memory_outlined,
                    title: 'No active environment',
                    message:
                        'Create or activate a virtual environment, then open Package Manager.',
                  )
                : isLoading
                ? const TimedLoadingIndicator()
                : packages.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No packages found',
                    message: query.isEmpty
                        ? 'Search PyPI to install your first package.'
                        : 'No installed packages match "$query".',
                    actionLabel: 'Search PyPI',
                    onAction: onSearchPyPI,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PackageTableHeader(),
                      Divider(height: 1, color: context.palette.borderSubtle),
                      Expanded(
                        child: ListView.builder(
                          itemCount: packages.length,
                          itemBuilder: (context, index) {
                            final package = packages[index];
                            return _PackageTableRow(
                              package: package,
                              selected: selected?.name == package.name,
                              onTap: () => onSelect(package),
                              onUpdate: () => onUpdate(package),
                              onUninstall: () => onUninstall(package),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared column widths for header + body rows.
abstract final class _PackageColumns {
  static const nameFlex = 3;
  static const versionFlex = 2;
  static const latestFlex = 2;
  static const summaryFlex = 4;
  static const actionsWidth = 80.0;
  static const rowHeight = 34.0;
  static const horizontalPadding = EdgeInsets.symmetric(horizontal: 16);
}

class _PackageTableHeader extends StatelessWidget {
  const _PackageTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.4,
      fontWeight: FontWeight.w600,
      color: context.palette.textMuted,
    );
    return Container(
      height: 28,
      color: context.palette.surface,
      padding: _PackageColumns.horizontalPadding,
      child: Row(
        children: [
          Expanded(
            flex: _PackageColumns.nameFlex,
            child: Text('NAME', style: style),
          ),
          Expanded(
            flex: _PackageColumns.versionFlex,
            child: Text('VERSION', style: style),
          ),
          Expanded(
            flex: _PackageColumns.latestFlex,
            child: Text('LATEST', style: style),
          ),
          Expanded(
            flex: _PackageColumns.summaryFlex,
            child: Text('SUMMARY', style: style),
          ),
          const SizedBox(width: _PackageColumns.actionsWidth),
        ],
      ),
    );
  }
}

class _PackageTableRow extends StatelessWidget {
  const _PackageTableRow({
    required this.package,
    required this.selected,
    required this.onTap,
    required this.onUpdate,
    required this.onUninstall,
  });

  final PackageInfo package;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final pkg = package;
    final latest = pkg.latestVersion;
    final showUpdate = pkg.updateAvailable && latest != null;

    return Material(
      color: selected ? context.palette.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.palette.surfaceHover,
        child: Container(
          height: _PackageColumns.rowHeight,
          padding: _PackageColumns.horizontalPadding,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.palette.borderSubtle),
              left: BorderSide(
                color: selected ? context.palette.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _PackageColumns.nameFlex,
                child: Text(
                  pkg.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                flex: _PackageColumns.versionFlex,
                child: Text(
                  pkg.version,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11.5,
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: _PackageColumns.latestFlex,
                child: Text(
                  showUpdate ? latest : (latest ?? '—'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11.5,
                    fontWeight: showUpdate ? FontWeight.w600 : FontWeight.w400,
                    color: showUpdate
                        ? context.palette.warning
                        : context.palette.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: _PackageColumns.summaryFlex,
                child: Builder(
                  builder: (context) {
                    final summary = pkg.summary?.trim() ?? '';
                    final label = summary.isNotEmpty ? summary : '—';
                    final text = Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.textMuted,
                      ),
                    );
                    if (summary.isEmpty) return text;
                    return Tooltip(
                      message: summary,
                      waitDuration: const Duration(milliseconds: 400),
                      child: text,
                    );
                  },
                ),
              ),
              SizedBox(
                width: _PackageColumns.actionsWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (showUpdate)
                      IconButton(
                        tooltip: 'Update to $latest',
                        onPressed: onUpdate,
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        icon: Icon(
                          Icons.upgrade,
                          color: context.palette.warning,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Uninstall',
                      onPressed: onUninstall,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      icon: Icon(
                        Icons.delete_outline,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
