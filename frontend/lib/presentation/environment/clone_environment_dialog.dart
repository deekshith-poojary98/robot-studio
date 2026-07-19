import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<String?> showCloneEnvironmentDialog(
  BuildContext context, {
  required String sourceName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => CloneEnvironmentDialog(sourceName: sourceName),
  );
}

class CloneEnvironmentDialog extends StatefulWidget {
  const CloneEnvironmentDialog({super.key, required this.sourceName});

  final String sourceName;

  @override
  State<CloneEnvironmentDialog> createState() => _CloneEnvironmentDialogState();
}

class _CloneEnvironmentDialogState extends State<CloneEnvironmentDialog> {
  late final TextEditingController _nameController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '${widget.sourceName}-copy');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Environment name is required');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clone Environment'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create a new virtual environment and copy packages from '
              '"${widget.sourceName}".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'New environment name',
              ),
              onChanged: (_) => setState(() => _error = null),
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
          child: const Text('Clone'),
        ),
      ],
    );
  }
}
