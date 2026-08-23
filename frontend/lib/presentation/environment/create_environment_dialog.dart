import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/platform/studio_file_picker.dart';
import '../../core/theme/app_theme.dart';
import 'python_install_guidance.dart';

Future<({String name, String pythonInterpreter, bool installRobot})?>
showCreateEnvironmentDialog(
  BuildContext context, {
  Future<List<PythonInterpreterInfo>> Function()? loadInterpreters,
}) {
  return showDialog<
    ({String name, String pythonInterpreter, bool installRobot})
  >(
    context: context,
    builder: (context) =>
        CreateEnvironmentDialog(loadInterpreters: loadInterpreters),
  );
}

class CreateEnvironmentDialog extends StatefulWidget {
  const CreateEnvironmentDialog({super.key, this.loadInterpreters});

  final Future<List<PythonInterpreterInfo>> Function()? loadInterpreters;

  @override
  State<CreateEnvironmentDialog> createState() =>
      _CreateEnvironmentDialogState();
}

class _CreateEnvironmentDialogState extends State<CreateEnvironmentDialog> {
  static const _customValue = '__custom__';

  final _nameController = TextEditingController();
  final _pythonController = TextEditingController();
  bool _installRobot = true;
  String? _error;
  bool _loadingInterpreters = false;
  bool _interpretersLoaded = false;
  List<PythonInterpreterInfo> _interpreters = const [];
  String? _selectedDropdownValue;

  @override
  void initState() {
    super.initState();
    _loadInterpreters();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pythonController.dispose();
    super.dispose();
  }

  Future<void> _loadInterpreters() async {
    final loader = widget.loadInterpreters;
    if (loader == null) {
      setState(() => _interpretersLoaded = true);
      return;
    }

    setState(() {
      _loadingInterpreters = true;
      _error = null;
    });
    try {
      final items = await loader();
      if (!mounted) return;
      setState(() {
        _interpreters = items;
        _loadingInterpreters = false;
        _interpretersLoaded = true;
        if (items.isNotEmpty && _pythonController.text.trim().isEmpty) {
          _selectedDropdownValue = items.first.path;
          _pythonController.text = items.first.path;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInterpreters = false;
        _interpretersLoaded = true;
        _error = 'Could not load interpreters: $error';
      });
    }
  }

  void _onDropdownChanged(String? value) {
    if (value == null) return;
    setState(() {
      _selectedDropdownValue = value;
      _error = null;
      if (value != _customValue) {
        _pythonController.text = value;
      }
    });
  }

  void _syncDropdownToPath(String path) {
    final match = _interpreters.where((item) => item.path == path);
    setState(() {
      _selectedDropdownValue = match.isEmpty
          ? (_interpreters.isEmpty ? null : _customValue)
          : path;
      _error = null;
    });
  }

  Future<void> _browsePython() async {
    try {
      final path = await StudioFilePicker.pickFile(
        dialogTitle: 'Select Python interpreter',
      );
      if (!mounted) return;
      if (path != null) {
        _pythonController.text = path;
        _syncDropdownToPath(path);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not open file picker: $error');
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final python = _pythonController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Environment name is required');
      return;
    }
    if (python.isEmpty) {
      setState(() {
        _error = _interpretersLoaded && _interpreters.isEmpty
            ? PythonInstallGuidance.summary
            : 'Python interpreter is required';
      });
      return;
    }
    Navigator.of(
      context,
    ).pop((name: name, pythonInterpreter: python, installRobot: _installRobot));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCustomPath =
        _selectedDropdownValue == _customValue ||
        _interpreters.isEmpty ||
        _selectedDropdownValue == null;
    final noPython =
        _interpretersLoaded && !_loadingInterpreters && _interpreters.isEmpty;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text('Create Environment', style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.wide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Environment name',
                hintText: 'robot-3.12',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            if (_loadingInterpreters)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (noPython) ...[
              Container(
                key: const Key('create-env.no-python'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.palette.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(
                    color: context.palette.warning.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      PythonInstallGuidance.summary,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      PythonInstallGuidance.createDialogBanner,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('create-env.refresh-interpreters'),
                        onPressed: _loadInterpreters,
                        icon: const Icon(Icons.refresh, size: 15),
                        label: const Text('Refresh'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_interpreters.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _selectedDropdownValue ?? _customValue,
                isExpanded: true,
                isDense: true,
                style: theme.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  labelText: 'Available interpreters',
                ),
                items: [
                  ..._interpreters.map(
                    (item) => DropdownMenuItem<String>(
                      value: item.path,
                      child: Text(
                        item.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: _customValue,
                    child: Text('Custom path…'),
                  ),
                ],
                onChanged: _onDropdownChanged,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _pythonController,
                    enabled: showCustomPath || _interpreters.isEmpty,
                    decoration: InputDecoration(
                      labelText: 'Python interpreter',
                      hintText: '/usr/bin/python3',
                      helperText: noPython
                          ? 'Browse to python3 after installing, or enter a path'
                          : showCustomPath
                          ? 'Enter a path or use Browse'
                          : 'Selected from the list above',
                    ),
                    onChanged: (value) {
                      _syncDropdownToPath(value.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _browsePython,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Browse…'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              onTap: () => setState(() => _installRobot = !_installRobot),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: _installRobot,
                        onChanged: (value) {
                          setState(() => _installRobot = value ?? false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Install Robot Framework',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: context.palette.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
