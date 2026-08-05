import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_badge.dart';

class PackageManagerPage extends StatelessWidget {
  const PackageManagerPage({
    super.key,
    required this.packages,
    required this.isLoading,
    required this.sort,
    required this.query,
    required this.selected,
    required this.robotInstalled,
    required this.robotVersion,
    required this.hasActiveEnvironment,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onSearchPyPI,
    required this.onImportRequirements,
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
  final String? robotVersion;
  final bool hasActiveEnvironment;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<PackageSort> onSortChanged;
  final VoidCallback onRefresh;
  final VoidCallback onSearchPyPI;
  final VoidCallback onImportRequirements;
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
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: hasActiveEnvironment ? onImportRequirements : null,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Import requirements…'),
                ),
                const SizedBox(width: 8),
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
                if (robotInstalled)
                  StatusBadge(
                    label: 'Robot Framework ${robotVersion ?? ''}'.trim(),
                    filled: true,
                    dotColor: context.palette.success,
                  )
                else
                  StatusBadge(
                    label: 'Robot Framework Missing',
                    filled: false,
                    dotColor: context.palette.warning,
                  ),
                if (!robotInstalled && hasActiveEnvironment) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: onInstallRobot,
                    child: const Text('Install Robot Framework'),
                  ),
                ],
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
                const SizedBox(width: 12),
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
          const SizedBox(height: 8),
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
                ? const Center(child: CircularProgressIndicator())
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
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: packages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final package = packages[index];
                      return _PackageRow(
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
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
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
    return Material(
      color: selected ? context.palette.accentSoft : context.palette.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? context.palette.accent : context.palette.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pkg.name,
                          style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pkg.updateAvailable)
                          StatusBadge(
                            label: 'Update',
                            filled: true,
                            dotColor: context.palette.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pkg.version}'
                      '${pkg.latestVersion != null ? ' → ${pkg.latestVersion}' : ''}'
                      '${pkg.summary != null ? '  ·  ${pkg.summary}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (pkg.updateAvailable)
                TextButton(onPressed: onUpdate, child: const Text('Update')),
              TextButton(
                onPressed: onUninstall,
                child: const Text('Uninstall'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
