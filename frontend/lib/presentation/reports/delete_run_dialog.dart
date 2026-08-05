import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/theme/app_theme.dart';

Future<bool?> showDeleteRunDialog(
  BuildContext context, {
  required ExecutionInfo run,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Run'),
      content: Text(
        'Delete report artifacts for "${run.projectName.isEmpty ? run.suite : run.projectName}"?\n\n'
        'This removes the Reports/Run-* folder and history metadata.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: context.palette.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
