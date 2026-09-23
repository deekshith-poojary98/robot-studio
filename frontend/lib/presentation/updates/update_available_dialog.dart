import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/updates/update_info.dart';

Future<void> openExternalUrl(String url) async {
  if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url]);
  } else {
    await Process.run('xdg-open', [url]);
  }
}

/// Offer download / release notes when a newer build is available.
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required String currentDisplayVersion,
  required UpdateInfo latest,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Text('Update available', style: theme.textTheme.titleLarge),
        content: SizedBox(
          width: AppDialogWidth.form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Robot Studio ${latest.displayVersion} is available. '
                'You have $currentDisplayVersion.',
                style: theme.textTheme.bodyMedium,
              ),
              if (latest.assetName != null &&
                  latest.assetName!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  latest.assetName!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: dialogContext.palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Later',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (latest.notesUrl != null && latest.notesUrl!.trim().isNotEmpty)
            TextButton(
              onPressed: () {
                unawaitedOpen(latest.notesUrl!);
              },
              child: const Text(
                'Release notes',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          if (latest.downloadUrl != null &&
              latest.downloadUrl!.trim().isNotEmpty)
            FilledButton(
              onPressed: () {
                unawaitedOpen(latest.downloadUrl!);
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Download',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      );
    },
  );
}

void unawaitedOpen(String url) {
  // Fire-and-forget; dialog callers don't need to await the OS open.
  openExternalUrl(url);
}

Future<void> showUpToDateDialog(
  BuildContext context, {
  required String currentDisplayVersion,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        'You\'re up to date',
        style: Theme.of(dialogContext).textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Text(
          'Robot Studio $currentDisplayVersion is the latest release.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(
            'OK',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
