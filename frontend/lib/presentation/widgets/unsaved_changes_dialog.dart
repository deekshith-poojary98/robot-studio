import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Result of an unsaved-changes confirmation.
enum UnsavedChangesChoice { save, discard, cancel }

/// Save / Don't Save (or Discard) / Cancel — compact desktop dialog chrome.
Future<UnsavedChangesChoice> showUnsavedChangesDialog(
  BuildContext context, {
  required String title,
  required String message,
  String saveLabel = 'Save',
  String discardLabel = "Don't Save",
}) async {
  final result = await showDialog<UnsavedChangesChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(title, style: Theme.of(dialogContext).textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Text(
          message,
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(UnsavedChangesChoice.cancel),
          child: const Text(
            'Cancel',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(UnsavedChangesChoice.discard),
          child: Text(
            discardLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(UnsavedChangesChoice.save),
          child: Text(
            saveLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return result ?? UnsavedChangesChoice.cancel;
}
