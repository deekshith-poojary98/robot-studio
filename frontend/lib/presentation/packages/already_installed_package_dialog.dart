import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Returns `true` when the user chooses Force Install, `false` / null on Cancel.
Future<bool?> showAlreadyInstalledPackageDialog(
  BuildContext context, {
  required String name,
  required String version,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        'Already Installed',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Text(
          '"$name" version $version is already installed in the active '
          'environment.\n\n'
          'Cancel to leave it alone, or Force Install to reinstall that same '
          'version.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Force Install'),
        ),
      ],
    ),
  );
}
