import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/gateway/models/settings_info.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/theme/app_theme.dart';
import 'editor_font_families.dart';

bool _sameSettings(AppSettings a, AppSettings b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);

/// Three-way merge so a settings change made elsewhere lands on the open page
/// without discarding fields the user is still editing: take `theirs` for
/// anything untouched, keep `mine` for anything already edited.
Map<String, dynamic> _mergeSettingsJson({
  required Map<String, dynamic> base,
  required Map<String, dynamic> mine,
  required Map<String, dynamic> theirs,
}) {
  final merged = <String, dynamic>{};
  for (final entry in theirs.entries) {
    final key = entry.key;
    final theirValue = entry.value;
    final baseValue = base[key];
    final myValue = mine[key];
    if (theirValue is Map<String, dynamic> &&
        baseValue is Map<String, dynamic> &&
        myValue is Map<String, dynamic>) {
      merged[key] = _mergeSettingsJson(
        base: baseValue,
        mine: myValue,
        theirs: theirValue,
      );
    } else if (jsonEncode(myValue) == jsonEncode(baseValue)) {
      merged[key] = theirValue;
    } else {
      merged[key] = myValue;
    }
  }
  return merged;
}

/// Settings categories. Add a value here to grow the page.
enum SettingsCategory {
  editor,
  execution,
  search,
  appearance;

  String get label => switch (this) {
    SettingsCategory.editor => 'Editor',
    SettingsCategory.execution => 'Execution',
    SettingsCategory.search => 'Search',
    SettingsCategory.appearance => 'Appearance',
  };

  IconData get icon => switch (this) {
    SettingsCategory.editor => Icons.edit_outlined,
    SettingsCategory.execution => Icons.play_circle_outline,
    SettingsCategory.search => Icons.search_outlined,
    SettingsCategory.appearance => Icons.palette_outlined,
  };

  String get description => switch (this) {
    SettingsCategory.editor => 'Saving, indentation, and font',
    SettingsCategory.execution => 'Run confirmations and result panels',
    SettingsCategory.search => 'Which files Find in Files reads',
    SettingsCategory.appearance => 'Theme and accent colour',
  };
}

/// Full-page settings — a center view, not a dialog, so categories can grow.
class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, required this.controller});

  final AppSettingsController controller;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  late AppSettings _draft;

  /// Last controller state this page reconciled against — the merge base for
  /// settings changed elsewhere (Edit ▸ Word Wrap, palette, another patch).
  late AppSettings _baseline;

  SettingsCategory _category = SettingsCategory.editor;
  bool _saving = false;
  String? _error;
  String? _savedNotice;

  final _extensionsController = TextEditingController();
  final _ignoreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseline = widget.controller.settings;
    _draft = _baseline;
    _syncTextFields();
    widget.controller.addListener(_onControllerChanged);
  }

  /// Adopt settings changed outside this page, keeping fields the user is
  /// mid-edit on. Without this, toggling Word Wrap from the Edit menu would
  /// leave a stale switch on screen and Save would write it back.
  void _onControllerChanged() {
    if (!mounted || _saving) return;
    final incoming = widget.controller.settings;
    if (_sameSettings(incoming, _baseline)) return;
    final merged = AppSettings.fromJson(
      _mergeSettingsJson(
        base: _baseline.toJson(),
        mine: _pendingSettings.toJson(),
        theirs: incoming.toJson(),
      ),
    );
    setState(() {
      _baseline = incoming;
      _draft = merged;
      _savedNotice = null;
      _reconcileTextFields();
    });
  }

  void _syncTextFields() {
    _extensionsController.text = _draft.search.contentSearchExtensions.join(
      ', ',
    );
    _ignoreController.text = _draft.search.ignorePatterns.join(', ');
  }

  /// Rewrite a text field only when its *value* moved, not its formatting, so
  /// an unrelated external change cannot reset a caret mid-word.
  void _reconcileTextFields() {
    if (!_sameList(
      _splitCsv(_extensionsController.text),
      _draft.search.contentSearchExtensions,
    )) {
      _extensionsController.text = _draft.search.contentSearchExtensions.join(
        ', ',
      );
    }
    if (!_sameList(
      _splitCsv(_ignoreController.text),
      _draft.search.ignorePatterns,
    )) {
      _ignoreController.text = _draft.search.ignorePatterns.join(', ');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _extensionsController.dispose();
    _ignoreController.dispose();
    super.dispose();
  }

  /// Text fields commit on save, so fold them in before comparing / sending.
  AppSettings get _pendingSettings => _draft.copyWith(
    search: _draft.search.copyWith(
      contentSearchExtensions: _splitCsv(_extensionsController.text),
      ignorePatterns: _splitCsv(_ignoreController.text),
    ),
  );

  bool get _isDirty => !_sameSettings(_pendingSettings, _baseline);

  void _markChanged() => setState(() => _savedNotice = null);

  Future<void> _save() async {
    final pending = _pendingSettings;
    setState(() {
      _saving = true;
      _error = null;
      _savedNotice = null;
      _draft = pending;
    });
    try {
      await widget.controller.update(pending);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _baseline = widget.controller.settings;
        _draft = _baseline;
        _savedNotice = 'Settings saved';
        _syncTextFields();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  void _discard() {
    setState(() {
      _baseline = widget.controller.settings;
      _draft = _baseline;
      _error = null;
      _savedNotice = null;
      _syncTextFields();
    });
  }

  Future<void> _reset() async {
    setState(() {
      _saving = true;
      _error = null;
      _savedNotice = null;
    });
    try {
      await widget.controller.reset();
      if (!mounted) return;
      setState(() {
        _baseline = widget.controller.settings;
        _draft = _baseline;
        _syncTextFields();
        _saving = false;
        _savedNotice = 'Restored defaults';
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
    return Container(
      color: context.palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _categoryRail(context),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: context.palette.borderSubtle,
                ),
                Expanded(child: _content(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _statusLine,
                  style: TextStyle(
                    fontSize: 12,
                    color: _error != null
                        ? context.palette.error
                        : (_isDirty
                              ? context.palette.warning
                              : context.palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _reset,
            child: const Text(
              'Restore Defaults',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: (_saving || !_isDirty) ? null : _discard,
            child: const Text(
              'Discard',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: (_saving || !_isDirty) ? null : _save,
            child: Text(
              _saving ? 'Saving…' : 'Save',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String get _statusLine {
    if (_error != null) return _error!;
    if (_isDirty) return 'Unsaved changes';
    return _savedNotice ?? 'Stored in ~/.robot-studio/settings.json';
  }

  Widget _categoryRail(BuildContext context) {
    return Container(
      width: 208,
      color: context.palette.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          for (final category in SettingsCategory.values)
            _CategoryTile(
              category: category,
              selected: category == _category,
              onTap: () => setState(() => _category = category),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: switch (_category) {
            SettingsCategory.editor => _editorSection(),
            SettingsCategory.execution => _executionSection(),
            SettingsCategory.search => _searchSection(),
            SettingsCategory.appearance => _appearanceSection(),
          },
        ),
      ),
    );
  }

  Widget _editorSection() {
    return _Section(
      title: 'Editor',
      children: [
        _SwitchRow(
          label: 'Auto Save',
          hint: 'Save changed files two seconds after you stop typing',
          value: _draft.editor.autoSave,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(autoSave: value),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Save Before Run',
          hint: 'Write pending edits before a suite starts',
          value: _draft.editor.saveBeforeRun,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(saveBeforeRun: value),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Word Wrap',
          value: _draft.editor.wordWrap,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(wordWrap: value),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Insert Spaces',
          hint: 'Indent with spaces instead of tab characters',
          value: _draft.editor.insertSpaces,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(insertSpaces: value),
              );
            });
          },
        ),
        _IntRow(
          label: 'Tab Width',
          hint: 'Spaces per indent level',
          value: _draft.editor.tabWidth,
          min: 1,
          max: 16,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(tabWidth: value),
              );
            });
          },
        ),
        _IntRow(
          label: 'Font Size',
          value: _draft.editor.fontSize,
          min: 9,
          max: 32,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(fontSize: value),
              );
            });
          },
        ),
        _DropdownRow<String>(
          label: 'Font Family',
          value: _draft.editor.fontFamily.trim().isEmpty
              ? 'Menlo'
              : _draft.editor.fontFamily.trim(),
          items: editorFontFamilyChoices(_draft.editor.fontFamily),
          labelFor: (item) => item,
          onChanged: (value) {
            if (value == null) return;
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                editor: _draft.editor.copyWith(fontFamily: value),
              );
            });
          },
        ),
      ],
    );
  }

  Widget _executionSection() {
    return _Section(
      title: 'Execution',
      children: [
        _NumberFieldRow(
          label: 'Large Run Threshold',
          hint: 'Ask for confirmation above this many tests',
          value: _draft.execution.largeRunThreshold,
          min: 1,
          max: 10000,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                execution: _draft.execution.copyWith(largeRunThreshold: value),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Reveal Execution On Run',
          hint: 'Bring the execution monitor to the front when a run starts',
          value: _draft.execution.revealExecutionOnRun,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                execution: _draft.execution.copyWith(
                  revealExecutionOnRun: value,
                ),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Auto Open Report On Failure',
          value: _draft.execution.autoOpenReportOnFailure,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                execution: _draft.execution.copyWith(
                  autoOpenReportOnFailure: value,
                ),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Stop Confirmation',
          hint: 'Confirm before stopping a running suite',
          value: _draft.execution.stopConfirmation,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                execution: _draft.execution.copyWith(stopConfirmation: value),
              );
            });
          },
        ),
      ],
    );
  }

  Widget _searchSection() {
    return _Section(
      title: 'Search',
      children: [
        _TextRow(
          label: 'Content Search Extensions',
          hint: '.robot, .py, .md',
          controller: _extensionsController,
          onChanged: (_) => _markChanged(),
        ),
        _TextRow(
          label: 'Ignore Patterns',
          hint: '.git, node_modules, build',
          controller: _ignoreController,
          onChanged: (_) => _markChanged(),
        ),
      ],
    );
  }

  Widget _appearanceSection() {
    return _Section(
      title: 'Appearance',
      children: [
        _DropdownRow<AppThemePreference>(
          label: 'Theme',
          value: _draft.appearance.theme,
          items: AppThemePreference.values,
          labelFor: (item) => item.label,
          onChanged: (value) {
            if (value == null) return;
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                appearance: _draft.appearance.copyWith(theme: value),
              );
            });
          },
        ),
        _DropdownRow<AppAccentPreference>(
          label: 'Accent',
          value: _draft.appearance.accent,
          items: AppAccentPreference.values,
          labelFor: (item) => item.label,
          leadingFor: (item) => Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: item.swatch,
              shape: BoxShape.circle,
              border: Border.all(color: context.palette.border),
            ),
          ),
          onChanged: (value) {
            if (value == null) return;
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                appearance: _draft.appearance.copyWith(accent: value),
              );
            });
          },
        ),
        _SwitchRow(
          label: 'Restore Last Project',
          hint: 'Reopen the last project or workspace when Robot Studio starts',
          value: _draft.appearance.restoreLastProject,
          onChanged: (value) {
            _markChanged();
            setState(() {
              _draft = _draft.copyWith(
                appearance: _draft.appearance.copyWith(
                  restoreLastProject: value,
                ),
              );
            });
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: selected ? context.palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          hoverColor: context.palette.surfaceHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  category.icon,
                  size: 15,
                  color: selected
                      ? context.palette.accent
                      : context.palette.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? context.palette.textPrimary
                          : context.palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.label, this.hint, required this.trailing});

  final String label;
  final String? hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      hint: hint,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    this.hint,
  });

  final String label;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      label: label,
      hint: hint,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
    this.hint,
  });

  final String label;
  final String? hint;
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
    return _RowShell(
      label: widget.label,
      hint: widget.hint,
      trailing: SizedBox(
        width: 88,
        height: 32,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
          ),
          onChanged: (raw) {
            final parsed = int.tryParse(raw.trim());
            if (parsed == null) return;
            widget.onChanged(parsed.clamp(widget.min, widget.max));
          },
        ),
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    this.hint,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
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
    this.leadingFor,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final Widget Function(T)? leadingFor;
  final ValueChanged<T?> onChanged;

  Widget _itemChild(T item) {
    final leading = leadingFor?.call(item);
    if (leading == null) {
      return Text(labelFor(item));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: AppSpacing.sm),
        Text(labelFor(item)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 12.5,
      height: 1.2,
      color: context.palette.textPrimary,
    );
    return _RowShell(
      label: label,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          padding: EdgeInsets.zero,
          style: textStyle,
          iconSize: 18,
          icon: Icon(
            Icons.expand_more,
            size: 18,
            color: context.palette.textMuted,
          ),
          // Only needed when the closed state shows a swatch — otherwise
          // Material's default closed item aligns more cleanly with the caret.
          selectedItemBuilder: leadingFor == null
              ? null
              : (context) => [for (final item in items) _itemChild(item)],
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: _itemChild(item)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
