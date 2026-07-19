import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<String?> showImportProjectDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const ImportProjectDialog(),
  );
}

class ImportProjectDialog extends StatefulWidget {
  const ImportProjectDialog({super.key});

  @override
  State<ImportProjectDialog> createState() => _ImportProjectDialogState();
}

class _ImportProjectDialogState extends State<ImportProjectDialog> {
  final _pathController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Robot Framework project',
      );
      if (!mounted) return;
      if (selected != null) {
        setState(() {
          _pathController.text = selected;
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
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Project path is required');
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Project'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose an existing Robot Framework project. Files stay in place; '
              'Robot Studio stores a reference only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'Project path',
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
          child: const Text('Import'),
        ),
      ],
    );
  }
}
