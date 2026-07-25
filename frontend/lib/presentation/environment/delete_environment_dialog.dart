import 'package:flutter/material.dart';

import '../../core/gateway/models/environment_info.dart';
import '../../core/theme/app_theme.dart';

Future<bool?> showDeleteEnvironmentDialog(
  BuildContext context, {
  required EnvironmentInfo environment,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => DeleteEnvironmentDialog(environment: environment),
  );
}

class DeleteEnvironmentDialog extends StatefulWidget {
  const DeleteEnvironmentDialog({super.key, required this.environment});

  final EnvironmentInfo environment;

  @override
  State<DeleteEnvironmentDialog> createState() =>
      _DeleteEnvironmentDialogState();
}

class _DeleteEnvironmentDialogState extends State<DeleteEnvironmentDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final env = widget.environment;
    return AlertDialog(
      title: const Text('Delete Environment'),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Remove "${env.name}" from this project?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (env.active) ...[
              const SizedBox(height: 12),
              const Text(
                'This environment is active and cannot be deleted. '
                'Activate another environment first.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete folder from disk'),
                value: _deleteFiles,
                onChanged: (value) {
                  setState(() => _deleteFiles = value ?? false);
                },
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
          onPressed: env.active
              ? null
              : () => Navigator.of(context).pop(_deleteFiles),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
