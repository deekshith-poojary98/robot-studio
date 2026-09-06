import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/gateway/models/run_configuration_info.dart';
import '../../core/theme/app_theme.dart';

Future<RunConfigurationDraft?> showRunConfigurationEditDialog(
  BuildContext context, {
  RunConfigurationInfo? existing,
  List<EnvironmentInfo> environments = const [],
}) {
  return showDialog<RunConfigurationDraft>(
    context: context,
    builder: (context) => RunConfigurationEditDialog(
      existing: existing,
      environments: environments,
    ),
  );
}

class RunConfigurationEditDialog extends StatefulWidget {
  const RunConfigurationEditDialog({
    super.key,
    this.existing,
    this.environments = const [],
  });

  final RunConfigurationInfo? existing;
  final List<EnvironmentInfo> environments;

  @override
  State<RunConfigurationEditDialog> createState() =>
      _RunConfigurationEditDialogState();
}

class _RunConfigurationEditDialogState
    extends State<RunConfigurationEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _include;
  late final TextEditingController _exclude;
  late final List<TextEditingController> _varKeys;
  late final List<TextEditingController> _varValues;
  late final List<TextEditingController> _variableFiles;
  late final List<TextEditingController> _extraArgs;
  String? _environmentId;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _include = TextEditingController(
      text: (existing?.includeTags ?? const []).join(', '),
    );
    _exclude = TextEditingController(
      text: (existing?.excludeTags ?? const []).join(', '),
    );
    _environmentId = existing?.environmentId;
    final variables = existing?.variables ?? const <RunVariableInfo>[];
    if (variables.isEmpty) {
      _varKeys = [TextEditingController()];
      _varValues = [TextEditingController()];
    } else {
      _varKeys = [
        for (final item in variables) TextEditingController(text: item.key),
      ];
      _varValues = [
        for (final item in variables) TextEditingController(text: item.value),
      ];
    }
    final files = existing?.variableFiles ?? const <String>[];
    _variableFiles = files.isEmpty
        ? [TextEditingController()]
        : [for (final path in files) TextEditingController(text: path)];
    final extra = existing?.extraRobotArgs ?? const <String>[];
    _extraArgs = extra.isEmpty
        ? [TextEditingController()]
        : [for (final token in extra) TextEditingController(text: token)];
  }

  @override
  void dispose() {
    _name.dispose();
    _include.dispose();
    _exclude.dispose();
    for (final item in _varKeys) {
      item.dispose();
    }
    for (final item in _varValues) {
      item.dispose();
    }
    for (final item in _variableFiles) {
      item.dispose();
    }
    for (final item in _extraArgs) {
      item.dispose();
    }
    super.dispose();
  }

  List<String> _splitTags(String raw) {
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final extra = [
      for (final item in _extraArgs)
        if (item.text.trim().isNotEmpty) item.text.trim(),
    ];
    Navigator.of(context).pop(
      RunConfigurationDraft(
        name: name,
        environmentId: _environmentId,
        includeTags: _splitTags(_include.text),
        excludeTags: _splitTags(_exclude.text),
        variables: [
          for (var i = 0; i < _varKeys.length; i++)
            if (_varKeys[i].text.trim().isNotEmpty)
              RunVariableInfo(
                key: _varKeys[i].text.trim(),
                value: _varValues[i].text,
              ),
        ],
        variableFiles: [
          for (final item in _variableFiles)
            if (item.text.trim().isNotEmpty) item.text.trim(),
        ],
        extraRobotArgs: extra,
      ),
    );
  }

  ButtonStyle get _textActionStyle => TextButton.styleFrom(
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final envIds = {for (final item in widget.environments) item.id};
    final selectedEnv =
        _environmentId != null && envIds.contains(_environmentId)
        ? _environmentId
        : null;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        _isEdit ? 'Edit Run Configuration' : 'New Run Configuration',
        style: theme.textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.wide,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: !_isEdit,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Environment for this run',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const Key('run-config.environment'),
                    isDense: true,
                    isExpanded: true,
                    value: selectedEnv,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Active environment'),
                      ),
                      ...widget.environments.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _environmentId = value),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pins this run only. Packages, Libraries, and language '
                'intelligence keep using the toolbar environment.',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _include,
                decoration: const InputDecoration(
                  labelText: 'Include tags',
                  hintText: 'smoke, critical',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _exclude,
                decoration: const InputDecoration(
                  labelText: 'Exclude tags',
                  hintText: 'wip',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Comma-separated. Multiple include tags are OR’d by Robot.',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Variables', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _varKeys.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _varKeys[i],
                          decoration: const InputDecoration(labelText: 'Key'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _varValues[i],
                          decoration: const InputDecoration(labelText: 'Value'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove variable',
                        onPressed: _varKeys.length == 1
                            ? () {
                                _varKeys[i].clear();
                                _varValues[i].clear();
                                setState(() {});
                              }
                            : () => setState(() {
                                _varKeys.removeAt(i).dispose();
                                _varValues.removeAt(i).dispose();
                              }),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _varKeys.add(TextEditingController());
                    _varValues.add(TextEditingController());
                  }),
                  style: _textActionStyle,
                  child: const Text('Add variable'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Variable files', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < _variableFiles.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _variableFiles[i],
                          decoration: const InputDecoration(
                            labelText: 'Project-relative path',
                            hintText: 'config/staging.py',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove variable file',
                        onPressed: () => setState(() {
                          if (_variableFiles.length == 1) {
                            _variableFiles[i].clear();
                            return;
                          }
                          _variableFiles.removeAt(i).dispose();
                        }),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(
                    () => _variableFiles.add(TextEditingController()),
                  ),
                  style: _textActionStyle,
                  child: const Text('Add variable file'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    'Advanced Robot arguments',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    'One argv token per row. Example: --listener then helper.qase_listener.QaseListener. '
                    'Studio keeps its progress listener; --outputdir / --log / --report are blocked.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    for (var i = 0; i < _extraArgs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _extraArgs[i],
                                decoration: const InputDecoration(
                                  labelText: 'Token',
                                  hintText: '--loglevel',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove argument',
                              onPressed: () => setState(() {
                                if (_extraArgs.length == 1) {
                                  _extraArgs[i].clear();
                                  return;
                                }
                                _extraArgs.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(
                          () => _extraArgs.add(TextEditingController()),
                        ),
                        style: _textActionStyle,
                        child: const Text('Add argument'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: context.palette.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: _textActionStyle,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
