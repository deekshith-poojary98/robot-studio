import 'package:flutter/material.dart';

import '../../core/gateway/models/plugin_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';

class PluginManagerPage extends StatelessWidget {
  const PluginManagerPage({
    super.key,
    required this.plugins,
    required this.isLoading,
    required this.selected,
    required this.onRefresh,
    required this.onSelect,
    required this.onEnable,
    required this.onDisable,
    required this.onReload,
    required this.onOpenFolder,
  });

  final List<PluginInfo> plugins;
  final bool isLoading;
  final PluginInfo? selected;
  final VoidCallback onRefresh;
  final ValueChanged<PluginInfo> onSelect;
  final ValueChanged<PluginInfo> onEnable;
  final ValueChanged<PluginInfo> onDisable;
  final ValueChanged<PluginInfo> onReload;
  final ValueChanged<PluginInfo> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
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
                        'Plugin Manager',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage built-in and workspace plugins.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : plugins.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: plugins.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final plugin = plugins[index];
                          return _PluginRow(
                            plugin: plugin,
                            selected: selected?.id == plugin.id,
                            onSelect: () => onSelect(plugin),
                            onEnable: () => onEnable(plugin),
                            onDisable: () => onDisable(plugin),
                            onReload: () => onReload(plugin),
                            onOpenFolder: () => onOpenFolder(plugin),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({
    required this.plugin,
    required this.selected,
    required this.onSelect,
    required this.onEnable,
    required this.onDisable,
    required this.onReload,
    required this.onOpenFolder,
  });

  final PluginInfo plugin;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onReload;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (plugin.status) {
      'enabled' => AppColors.success,
      'failed' => AppColors.error,
      'disabled' => AppColors.warning,
      _ => AppColors.textMuted,
    };

    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${plugin.id} • v${plugin.version}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: plugin.status.toUpperCase(),
                    filled: plugin.enabled,
                    dotColor: statusColor,
                  ),
                  if (plugin.isBuiltin) ...[
                    const SizedBox(width: 8),
                    const StatusBadge(label: 'BUILT-IN'),
                  ],
                ],
              ),
              if (plugin.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(plugin.description, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (plugin.capabilities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: plugin.capabilities
                      .map((cap) => Chip(label: Text(cap), visualDensity: VisualDensity.compact))
                      .toList(),
                ),
              ],
              if (plugin.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  plugin.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: plugin.enabled ? null : onEnable,
                    child: const Text('Enable'),
                  ),
                  TextButton(
                    onPressed: plugin.isBuiltin || !plugin.enabled ? null : onDisable,
                    child: const Text('Disable'),
                  ),
                  TextButton(onPressed: onReload, child: const Text('Reload')),
                  TextButton(
                    onPressed: plugin.path == null ? null : onOpenFolder,
                    child: const Text('Open Folder'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No plugins discovered yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Add plugins to Workspace/Plugins or ~/.robotstudio/plugins.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
