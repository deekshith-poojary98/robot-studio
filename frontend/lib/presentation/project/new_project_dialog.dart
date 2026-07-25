import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<String?> showNewProjectDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const NewProjectDialog(),
  );
}

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _nameController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Project name is required');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Project'),
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
                labelText: 'Project name',
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (_nameController.text.trim().isNotEmpty) {
                  _submit();
                }
              },
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
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
