import 'package:flutter/material.dart';

import '../../core/gateway/models/plugin_info.dart';
import '../../core/theme/app_theme.dart';

class PluginDetailsPanel extends StatelessWidget {
  const PluginDetailsPanel({
    super.key,
    required this.plugin,
    required this.onEnable,
    required this.onDisable,
    required this.onReload,
  });

  final PluginInfo? plugin;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final selected = plugin;
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: selected == null
          ? Center(
              child: Text(
                'Select a plugin to view details.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(selected.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${selected.id} • v${selected.version}'),
                if (selected.author.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Author: ${selected.author}'),
                ],
                const SizedBox(height: 8),
                Text(selected.description.isEmpty ? 'No description.' : selected.description),
                const SizedBox(height: 12),
                Text('Status: ${selected.status}'),
                if (selected.path != null) ...[
                  const SizedBox(height: 8),
                  Text('Path: ${selected.path!}', style: Theme.of(context).textTheme.bodySmall),
                ],
                if (selected.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    selected.error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: onEnable, child: const Text('Enable')),
                    OutlinedButton(
                      onPressed: selected.isBuiltin ? null : onDisable,
                      child: const Text('Disable'),
                    ),
                    OutlinedButton(onPressed: onReload, child: const Text('Reload')),
                  ],
                ),
              ],
            ),
    );
  }
}

Future<void> showPluginErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
