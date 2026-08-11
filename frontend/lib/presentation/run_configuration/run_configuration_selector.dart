import 'package:flutter/material.dart';

import '../../core/gateway/models/run_configuration_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_menu.dart';

class RunConfigurationSelector extends StatelessWidget {
  const RunConfigurationSelector({
    super.key,
    required this.configurations,
    required this.activeId,
    required this.enabled,
    required this.onSelected,
    required this.onNew,
    required this.onManage,
  });

  final List<RunConfigurationInfo> configurations;
  final String? activeId;
  final bool enabled;
  final ValueChanged<String?> onSelected;
  final VoidCallback onNew;
  final VoidCallback onManage;

  String get _label {
    if (activeId == null) return 'Default';
    for (final item in configurations) {
      if (item.id == activeId) return item.name;
    }
    return 'Default';
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: AppControlHeight.toolbarChip,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 14, color: context.palette.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              _label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: context.palette.textMuted,
          ),
        ],
      ),
    );

    if (!enabled) {
      return Tooltip(
        message: 'Open a project to choose a run configuration',
        child: chip,
      );
    }

    return PopupMenuButton<String>(
      key: const Key('toolbar.run-configuration'),
      tooltip:
          'Run configuration — supplies tags, variables, and optional '
          'environment for this run only',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == '__new__') {
          onNew();
          return;
        }
        if (value == '__manage__') {
          onManage();
          return;
        }
        if (value == '__default__') {
          onSelected(null);
          return;
        }
        onSelected(value);
      },
      itemBuilder: (context) => [
        AppCheckedPopupMenuItem<String>(
          value: '__default__',
          checked: activeId == null,
          child: const Text('Default'),
        ),
        ...configurations.map(
          (item) => AppCheckedPopupMenuItem<String>(
            value: item.id,
            checked: item.id == activeId,
            child: Text(item.name),
          ),
        ),
        const AppPopupMenuDivider(),
        const AppPopupMenuItem<String>(
          value: '__new__',
          child: Text('New Configuration…'),
        ),
        const AppPopupMenuItem<String>(
          value: '__manage__',
          child: Text('Manage Configurations…'),
        ),
      ],
      child: chip,
    );
  }
}
