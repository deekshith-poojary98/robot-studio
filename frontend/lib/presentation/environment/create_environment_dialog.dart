import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<({String name, String pythonInterpreter, bool installRobot})?>
    showCreateEnvironmentDialog(BuildContext context) {
  return showDialog<
      ({String name, String pythonInterpreter, bool installRobot})>(
    context: context,
    builder: (context) => const CreateEnvironmentDialog(),
  );
}

class CreateEnvironmentDialog extends StatefulWidget {
  const CreateEnvironmentDialog({super.key});

  @override
  State<CreateEnvironmentDialog> createState() =>
      _CreateEnvironmentDialogState();
}

class _CreateEnvironmentDialogState extends State<CreateEnvironmentDialog> {
  final _nameController = TextEditingController();
  final _pythonController = TextEditingController();
  bool _installRobot = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _pythonController.dispose();
    super.dispose();
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
        setState(() {
          _pythonController.text = path;
          _error = null;
        });
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
    return AlertDialog(
      title: const Text('Create Environment'),
      content: SizedBox(
        width: 480,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pythonController,
                    decoration: const InputDecoration(
                      labelText: 'Python interpreter',
                      hintText: '/usr/bin/python3',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _browsePython,
                  child: const Text('Browse'),
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
