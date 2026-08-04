import 'package:flutter/material.dart';

import '../../core/gateway/models/settings_info.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/app_theme.dart';

Future<void> showPreferencesDialog(
  BuildContext context, {
  required AppSettingsController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => PreferencesDialog(controller: controller),
  );
}

class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({super.key, required this.controller});

  final AppSettingsController controller;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late AppSettings _draft;
  bool _saving = false;
  String? _error;

  final _fontFamilyController = TextEditingController();
  final _extensionsController = TextEditingController();
  final _ignoreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.settings;
    _syncTextFields();
    widget.controller.addListener(_onController);
  }

  void _onController() {
    if (!mounted || _saving) return;
    // Keep dialog in sync if settings reload externally.
  }

  void _syncTextFields() {
    _fontFamilyController.text = _draft.editor.fontFamily;
    _extensionsController.text =
        _draft.search.contentSearchExtensions.join(', ');
    _ignoreController.text = _draft.search.ignorePatterns.join(', ');
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _fontFamilyController.dispose();
    _extensionsController.dispose();
    _ignoreController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _draft = _draft.copyWith(
        editor: _draft.editor.copyWith(
          fontFamily: _fontFamilyController.text.trim().isEmpty
              ? 'Menlo'
              : _fontFamilyController.text.trim(),
        ),
        search: _draft.search.copyWith(
          contentSearchExtensions: _splitCsv(_extensionsController.text),
          ignorePatterns: _splitCsv(_ignoreController.text),
        ),
      );
    });
    try {
      await widget.controller.update(_draft);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  Future<void> _reset() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.reset();
      if (!mounted) return;
      setState(() {
        _draft = widget.controller.settings;
        _syncTextFields();
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(RegExp(r'[,;\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text('Preferences', style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.wide,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Editor',
                  children: [
                    _SwitchRow(
                      label: 'Auto Save',
                      value: _draft.editor.autoSave,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(autoSave: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Save Before Run',
                      value: _draft.editor.saveBeforeRun,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(saveBeforeRun: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Word Wrap',
                      value: _draft.editor.wordWrap,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(wordWrap: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Insert Spaces',
                      value: _draft.editor.insertSpaces,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(insertSpaces: value),
                        );
                      }),
                    ),
                    _IntRow(
                      label: 'Tab Width',
                      value: _draft.editor.tabWidth,
                      min: 1,
                      max: 16,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(tabWidth: value),
                        );
                      }),
                    ),
                    _IntRow(
                      label: 'Font Size',
                      value: _draft.editor.fontSize,
                      min: 9,
                      max: 32,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          editor: _draft.editor.copyWith(fontSize: value),
                        );
                      }),
                    ),
                    _TextRow(
                      label: 'Font Family',
                      controller: _fontFamilyController,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Execution',
                  children: [
                    _NumberFieldRow(
                      label: 'Large Run Threshold',
                      value: _draft.execution.largeRunThreshold,
                      min: 1,
                      max: 10000,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          execution: _draft.execution
                              .copyWith(largeRunThreshold: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Reveal Execution On Run',
                      value: _draft.execution.revealExecutionOnRun,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          execution: _draft.execution
                              .copyWith(revealExecutionOnRun: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Auto Open Report On Failure',
                      value: _draft.execution.autoOpenReportOnFailure,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          execution: _draft.execution
                              .copyWith(autoOpenReportOnFailure: value),
                        );
                      }),
                    ),
                    _SwitchRow(
                      label: 'Stop Confirmation',
                      value: _draft.execution.stopConfirmation,
                      onChanged: (value) => setState(() {
                        _draft = _draft.copyWith(
                          execution: _draft.execution
                              .copyWith(stopConfirmation: value),
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Search',
                  children: [
                    _TextRow(
                      label: 'Content Search Extensions',
                      controller: _extensionsController,
                      hint: '.robot, .py, .md',
                    ),
                    _TextRow(
                      label: 'Ignore Patterns',
                      controller: _ignoreController,
                      hint: '.git, node_modules, build',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Appearance',
                  children: [
                    _DropdownRow<AppThemePreference>(
                      label: 'Theme',
                      value: _draft.appearance.theme,
                      items: AppThemePreference.values,
                      labelFor: (item) => item.label,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _draft = _draft.copyWith(
                            appearance:
                                _draft.appearance.copyWith(theme: value),
                          );
                        });
                      },
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _saving ? null : _reset,
          child: const Text(
            'Reset',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? 'Saving…' : 'Save',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _IntRow extends StatelessWidget {
  const _IntRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: value <= min ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: value >= max ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _NumberFieldRow extends StatefulWidget {
  const _NumberFieldRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberFieldRow> createState() => _NumberFieldRowState();
}

class _NumberFieldRowState extends State<_NumberFieldRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _NumberFieldRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          SizedBox(
            width: 72,
            height: 32,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (raw) {
                final parsed = int.tryParse(raw.trim());
                if (parsed == null) return;
                widget.onChanged(parsed.clamp(widget.min, widget.max));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            items: [
              for (final item in items)
                DropdownMenuItem(value: item, child: Text(labelFor(item))),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
