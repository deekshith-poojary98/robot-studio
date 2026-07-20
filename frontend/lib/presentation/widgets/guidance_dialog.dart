import 'package:flutter/material.dart';

/// Soft guidance dialog with a primary next-step action (and optional secondary).
Future<void> showGuidanceDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String primaryLabel,
  required VoidCallback onPrimary,
  String? secondaryLabel,
  VoidCallback? onSecondary,
  String dismissLabel = 'Cancel',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dismissLabel),
        ),
        if (secondaryLabel != null)
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onSecondary?.call();
            },
            child: Text(secondaryLabel),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onPrimary();
          },
          child: Text(primaryLabel),
        ),
      ],
    ),
  );
}
