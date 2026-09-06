import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/transport_gateway.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/error_dialog.dart';
import '../widgets/status_badge.dart';
import 'run_configuration_edit_dialog.dart';

Future<void> showManageRunConfigurationsDialog(
  BuildContext context, {
  required TransportGateway gateway,
  List<EnvironmentInfo> environments = const [],
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ManageRunConfigurationsDialog(
      gateway: gateway,
      environments: environments,
    ),
  );
}

class ManageRunConfigurationsDialog extends StatefulWidget {
  const ManageRunConfigurationsDialog({
    super.key,
    required this.gateway,
    this.environments = const [],
  });

  final TransportGateway gateway;
  final List<EnvironmentInfo> environments;

  @override
  State<ManageRunConfigurationsDialog> createState() =>
      _ManageRunConfigurationsDialogState();
}

class _ManageRunConfigurationsDialogState
    extends State<ManageRunConfigurationsDialog> {
  RunConfigurationListInfo _bundle = const RunConfigurationListInfo();
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final bundle = await widget.gateway.listRunConfigurations();
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showFriendlyErrorDialog(
        context: context,
        title: 'Run configurations',
        error: error,
      );
    }
  }

  Future<void> _create() async {
    final draft = await showRunConfigurationEditDialog(
      context,
      environments: widget.environments,
    );
    if (draft == null || !mounted) return;
    try {
      await widget.gateway.createRunConfiguration(draft);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showFriendlyErrorDialog(
        context: context,
        title: 'Create run configuration',
        error: error,
      );
    }
  }

  Future<void> _edit(RunConfigurationInfo item) async {
    final draft = await showRunConfigurationEditDialog(
      context,
      existing: item,
      environments: widget.environments,
    );
    if (draft == null || !mounted) return;
    try {
      await widget.gateway.updateRunConfiguration(item.id, draft);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showFriendlyErrorDialog(
        context: context,
        title: 'Update run configuration',
        error: error,
      );
    }
  }

  Future<void> _duplicate(RunConfigurationInfo item) async {
    setState(() => _busyId = item.id);
    try {
      await widget.gateway.duplicateRunConfiguration(item.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showFriendlyErrorDialog(
        context: context,
        title: 'Duplicate run configuration',
        error: error,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(RunConfigurationInfo item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Text(
          'Delete configuration?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: SizedBox(
          width: AppDialogWidth.form,
          child: Text('Delete “${item.name}”? This cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: _textActionStyle,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: _filledActionStyle,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.gateway.deleteRunConfiguration(item.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showFriendlyErrorDialog(
        context: context,
        title: 'Delete run configuration',
        error: error,
      );
    }
  }

  Future<void> _use(RunConfigurationInfo item) async {
    try {
      await widget.gateway.activateRunConfiguration(item.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showFriendlyErrorDialog(
        context: context,
        title: 'Select run configuration',
        error: error,
      );
    }
  }

  String? _environmentLabel(RunConfigurationInfo item) {
    final id = item.environmentId;
    if (id == null || id.isEmpty) return null;
    for (final env in widget.environments) {
      if (env.id == id) return env.name;
    }
    return 'Pinned env';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text('Run Configurations', style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.wide,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _bundle.configurations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.playlist_add_check_rounded,
                        size: 28,
                        color: context.palette.textMuted,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No run configurations yet',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Create one to pin tags, variables, or an environment '
                        'for the next run.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _bundle.configurations.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final item = _bundle.configurations[index];
                  final active = item.id == _bundle.activeId;
                  final busy = _busyId == item.id;
                  return _ConfigurationRow(
                    item: item,
                    active: active,
                    busy: busy,
                    subtitle: _subtitle(
                      item,
                      environmentLabel: _environmentLabel(item),
                    ),
                    onUse: () => unawaited(_use(item)),
                    onDuplicate: () => unawaited(_duplicate(item)),
                    onEdit: () => unawaited(_edit(item)),
                    onDelete: () => unawaited(_delete(item)),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_create()),
          style: _textActionStyle,
          child: const Text('New Configuration…'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: _filledActionStyle,
          child: const Text('Done'),
        ),
      ],
    );
  }

  String _subtitle(
    RunConfigurationInfo item, {
    required String? environmentLabel,
  }) {
    final bits = <String>[
      ?environmentLabel,
      if (item.includeTags.isNotEmpty) '+${item.includeTags.join(', ')}',
      if (item.excludeTags.isNotEmpty) '−${item.excludeTags.join(', ')}',
      if (item.variables.isNotEmpty)
        '${item.variables.length} '
            '${item.variables.length == 1 ? 'variable' : 'variables'}',
      if (item.variableFiles.isNotEmpty)
        '${item.variableFiles.length} '
            '${item.variableFiles.length == 1 ? 'var file' : 'var files'}',
      if (item.extraRobotArgs.isNotEmpty) 'advanced args',
    ];
    return bits.isEmpty ? 'Default · no filters' : bits.join(' · ');
  }

  static final _textActionStyle = TextButton.styleFrom(
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

  static final _filledActionStyle = FilledButton.styleFrom(
    minimumSize: const Size(76, 36),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );
}

class _ConfigurationRow extends StatefulWidget {
  const _ConfigurationRow({
    required this.item,
    required this.active,
    required this.busy,
    required this.subtitle,
    required this.onUse,
    required this.onDuplicate,
    required this.onEdit,
    required this.onDelete,
  });

  final RunConfigurationInfo item;
  final bool active;
  final bool busy;
  final String subtitle;
  final VoidCallback onUse;
  final VoidCallback onDuplicate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ConfigurationRow> createState() => _ConfigurationRowState();
}

class _ConfigurationRowState extends State<_ConfigurationRow> {
  bool _hovered = false;

  static final _actionStyle = TextButton.styleFrom(
    minimumSize: const Size(0, 28),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = widget.active;
    final busy = widget.busy;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: active
              ? palette.accentSoft
              : _hovered
              ? palette.surfaceHover
              : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: active
                ? palette.accent.withValues(alpha: 0.45)
                : palette.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: AppSpacing.sm),
                        StatusBadge(
                          label: 'Selected',
                          filled: true,
                          dotColor: palette.accent,
                          height: 20,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (!active)
              TextButton(
                onPressed: busy ? null : widget.onUse,
                style: _actionStyle,
                child: const Text('Use'),
              ),
            TextButton(
              key: Key('run-config.duplicate.${widget.item.id}'),
              onPressed: busy ? null : widget.onDuplicate,
              style: _actionStyle,
              child: const Text('Duplicate'),
            ),
            TextButton(
              onPressed: busy ? null : widget.onEdit,
              style: _actionStyle,
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: busy ? null : widget.onDelete,
              style: _actionStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(palette.error),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
