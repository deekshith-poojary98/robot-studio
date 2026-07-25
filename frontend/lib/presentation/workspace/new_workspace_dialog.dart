import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<({String name, String location})?> showNewWorkspaceDialog(
  BuildContext context,
) {
  return showDialog<({String name, String location})>(
    context: context,
    builder: (context) => const NewWorkspaceDialog(),
  );
}

class NewWorkspaceDialog extends StatefulWidget {
  const NewWorkspaceDialog({super.key});

  @override
  State<NewWorkspaceDialog> createState() => _NewWorkspaceDialogState();
}

class _NewWorkspaceDialogState extends State<NewWorkspaceDialog> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select workspace location',
      );
      if (!mounted) return;
      if (selected != null) {
        setState(() {
          _locationController.text = selected;
          _error = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open folder picker: $error';
      });
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Workspace name is required');
      return;
    }
    if (location.isEmpty) {
      setState(() => _error = 'Workspace location is required');
      return;
    }

    Navigator.of(context).pop((name: name, location: location));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Workspace'),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Workspace name',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _browse,
                  child: const Text('Browse'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
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
