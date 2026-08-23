import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/detail_property_table.dart';
import '../widgets/status_badge.dart';

class PackageDetailsPanel extends StatelessWidget {
  const PackageDetailsPanel({
    super.key,
    required this.package,
    this.onUpdate,
    this.onUninstall,
    this.onBack,
  });

  final PackageInfo package;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final pkg = package;
    return Container(
      color: context.palette.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (onBack != null) ...[
                    IconButton(
                      tooltip: 'Back to packages',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back, size: 18),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 28,
                    color: context.palette.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pkg.name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 20),
                    ),
                  ),
                  if (pkg.updateAvailable)
                    StatusBadge(
                      label: 'Update available',
                      filled: true,
                      dotColor: context.palette.warning,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pkg.updateAvailable && onUpdate != null)
                    FilledButton(
                      onPressed: onUpdate,
                      child: const Text('Update'),
                    ),
                  if (onUninstall != null)
                    OutlinedButton(
                      onPressed: onUninstall,
                      child: const Text('Uninstall'),
                    ),
                  if (pkg.homepage != null && pkg.homepage!.isNotEmpty)
                    TextButton(
                      onPressed: () => _openHomepage(pkg.homepage!),
                      child: const Text('Open Homepage'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              DetailPropertyTable(
                rows: [
                  DetailPropertyRow(
                    label: 'Installed version',
                    value: pkg.version,
                  ),
                  DetailPropertyRow(
                    label: 'Latest version',
                    value: pkg.latestVersion ?? pkg.version,
                  ),
                  DetailPropertyRow(
                    label: 'Summary',
                    value: pkg.summary ?? '—',
                  ),
                  DetailPropertyRow(label: 'Author', value: pkg.author ?? '—'),
                  DetailPropertyRow(
                    label: 'Homepage',
                    value: pkg.homepage ?? '—',
                  ),
                  DetailPropertyRow(
                    label: 'License',
                    value: pkg.license ?? '—',
                  ),
                  DetailPropertyRow(
                    label: 'Dependencies',
                    value: pkg.requires.isEmpty ? '—' : pkg.requires.join('\n'),
                  ),
                  DetailPropertyRow(
                    label: 'Install location',
                    value: pkg.location ?? '—',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHomepage(String homepage) async {
    if (Platform.isMacOS) {
      await Process.run('open', [homepage]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', homepage]);
    } else {
      await Process.run('xdg-open', [homepage]);
    }
  }
}
