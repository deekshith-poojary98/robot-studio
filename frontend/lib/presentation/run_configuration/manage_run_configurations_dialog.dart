import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/gateway/transport_gateway.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/error_dialog.dart';
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        'Manage Run Configurations',
        style: theme.textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.wide,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _bundle.configurations.isEmpty
            ? Center(
                child: Text(
                  'No run configurations yet.\nCreate one to pin tags, variables, '
                  'or an environment for a run.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _bundle.configurations.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: context.palette.borderSubtle),
                itemBuilder: (context, index) {
                  final item = _bundle.configurations[index];
                  final active = item.id == _bundle.activeId;
                  final busy = _busyId == item.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(item, active: active),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_use(item)),
                              child: Text(active ? 'Selected' : 'Use'),
                            ),
                            TextButton(
                              key: Key('run-config.duplicate.${item.id}'),
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_duplicate(item)),
                              child: const Text('Duplicate'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_edit(item)),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_delete(item)),
                              style: TextButton.styleFrom(
                                foregroundColor: context.palette.error,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(_create()),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('New Configuration…'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }

  String _subtitle(RunConfigurationInfo item, {required bool active}) {
    final bits = <String>[
      if (active) 'Selected',
      if (item.includeTags.isNotEmpty) 'include ${item.includeTags.join(', ')}',
      if (item.excludeTags.isNotEmpty) 'exclude ${item.excludeTags.join(', ')}',
    ];
    return bits.isEmpty ? 'No filters' : bits.join(' · ');
  }
}
