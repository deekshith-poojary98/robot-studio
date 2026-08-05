import 'package:flutter/material.dart';

import '../../core/gateway/models/plugin_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeleton_list.dart';
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
                        'Plugin Manager',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage built-in and project plugins.',
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
                ? const SkeletonList(rows: 4)
                : plugins.isEmpty
                ? const EmptyState(
                    icon: Icons.extension_outlined,
                    title: 'No plugins discovered',
                    message:
                        'Add plugins to the project Plugins/ folder or ~/.robotstudio/plugins.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: plugins.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
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
      'enabled' => context.palette.success,
      'failed' => context.palette.error,
      'disabled' => context.palette.warning,
      _ => context.palette.textMuted,
    };

    return Material(
      color: selected ? context.palette.accentSoft : context.palette.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? context.palette.accent
                  : context.palette.borderSubtle,
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
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        StatusBadge(
                          label: plugin.status.toUpperCase(),
                          filled: plugin.enabled,
                          dotColor: statusColor,
                        ),
                        if (plugin.isBuiltin)
                          const StatusBadge(label: 'BUILT-IN'),
                      ],
                    ),
                  ),
                ],
              ),
              if (plugin.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  plugin.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (plugin.capabilities.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: plugin.capabilities
                      .map(
                        (cap) => Chip(
                          label: Text(cap),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (plugin.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  plugin.error!,
                  style: TextStyle(color: context.palette.error, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  if (!plugin.enabled)
                    TextButton(onPressed: onEnable, child: const Text('Enable'))
                  else
                    TextButton(
                      onPressed: plugin.isBuiltin ? null : onDisable,
                      child: Text(plugin.isBuiltin ? 'Built-in' : 'Disable'),
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
