import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/theme/app_theme.dart';

Future<({String name, String pythonInterpreter, bool installRobot})?>
    showCreateEnvironmentDialog(
  BuildContext context, {
  Future<List<PythonInterpreterInfo>> Function()? loadInterpreters,
}) {
  return showDialog<
      ({String name, String pythonInterpreter, bool installRobot})>(
    context: context,
    builder: (context) => CreateEnvironmentDialog(
      loadInterpreters: loadInterpreters,
    ),
  );
}

class CreateEnvironmentDialog extends StatefulWidget {
  const CreateEnvironmentDialog({
    super.key,
    this.loadInterpreters,
  });

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
    if (loader == null) return;

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
        if (items.isNotEmpty && _pythonController.text.trim().isEmpty) {
          _selectedDropdownValue = items.first.path;
          _pythonController.text = items.first.path;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInterpreters = false;
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
      _selectedDropdownValue =
          match.isEmpty ? (_interpreters.isEmpty ? null : _customValue) : path;
      _error = null;
    });
  }

  Future<void> _browsePython() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Python interpreter',
        type: FileType.any,
        allowMultiple: false,
      );
      if (!mounted) return;
      final path = result?.files.single.path;
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
      setState(() => _error = 'Python interpreter is required');
      return;
    }
    Navigator.of(context).pop((
      name: name,
      pythonInterpreter: python,
      installRobot: _installRobot,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final showCustomPath = _selectedDropdownValue == _customValue ||
        _interpreters.isEmpty ||
        _selectedDropdownValue == null;

    return AlertDialog(
      title: const Text('Create Environment'),
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
            else if (_interpreters.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _selectedDropdownValue ?? _customValue,
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 12.5),
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
                      helperText: showCustomPath
                          ? 'Enter a path or use Browse'
                          : 'Selected from the list above',
                    ),
                    onChanged: (value) {
                      _syncDropdownToPath(value.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _browsePython,
                    child: const Text('Browse'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Install Robot Framework'),
              value: _installRobot,
              onChanged: (value) {
                setState(() => _installRobot = value ?? false);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
