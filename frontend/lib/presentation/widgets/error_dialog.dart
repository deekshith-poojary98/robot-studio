import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// User-facing failure dialog: what happened, how to fix it, raw detail hidden
/// behind "Show details" so nobody reads a stack trace by accident.
Future<void> showFriendlyErrorDialog({
  required BuildContext context,
  required String title,
  required Object error,
  String? recovery,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final details = error.toString();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _FriendlyErrorDialog(
      title: title,
      summary: friendlyErrorSummary(details),
      recovery: recovery ?? friendlyErrorRecovery(details),
      details: details,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// Turns transport/exception noise into one plain sentence.
String friendlyErrorSummary(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('connection refused') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception')) {
    return 'Robot Studio could not reach its backend service.';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'The operation took too long and was stopped.';
  }
  if (text.contains('permission denied') || text.contains('errno 13')) {
    return 'Robot Studio is not allowed to use that file or folder.';
  }
  if (text.contains('already exists') || text.contains('errno 17')) {
    return 'Something with that name already exists.';
  }
  if (text.contains('not found') ||
      text.contains('no such file') ||
      text.contains('errno 2')) {
    return 'Robot Studio could not find that file or folder.';
  }
  if (text.contains('no space left')) {
    return 'The disk is full, so the change could not be saved.';
  }
  if (text.contains('environment')) {
    return 'The Python environment could not complete this request.';
  }
  return 'That action did not finish.';
}

/// Suggests the next step for the same error families.
String friendlyErrorRecovery(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('connection refused') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception')) {
    return 'Make sure the backend is running, then try again.';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'Try again. If it keeps timing out, the project may be very large.';
  }
  if (text.contains('permission denied') || text.contains('errno 13')) {
    return 'Pick a different location, or fix the folder permissions.';
  }
  if (text.contains('already exists') || text.contains('errno 17')) {
    return 'Choose another name, or open the existing item instead.';
  }
  if (text.contains('not found') ||
      text.contains('no such file') ||
      text.contains('errno 2')) {
    return 'It may have been moved or deleted. Refresh and try again.';
  }
  if (text.contains('no space left')) {
    return 'Free up disk space, then retry.';
  }
  if (text.contains('environment')) {
    return 'Check the active environment in the toolbar, then try again.';
  }
  return 'Try again. If it keeps failing, check the details below.';
}

class _FriendlyErrorDialog extends StatefulWidget {
  const _FriendlyErrorDialog({
    required this.title,
    required this.summary,
    required this.recovery,
    required this.details,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String summary;
  final String recovery;
  final String details;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_FriendlyErrorDialog> createState() => _FriendlyErrorDialogState();
}

class _FriendlyErrorDialogState extends State<_FriendlyErrorDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.summary),
            const SizedBox(height: 10),
            Text(widget.recovery, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('error.show-details'),
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(_showDetails ? 'Hide details' : 'Show details'),
              ),
            ),
            if (_showDetails) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.details,
                    style: const TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => unawaitedCopy(widget.details),
                  icon: const Icon(Icons.copy_all_outlined, size: 15),
                  label: const Text('Copy details'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.actionLabel != null && widget.onAction != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onAction!();
            },
            child: Text(widget.actionLabel!),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

void unawaitedCopy(String value) {
  Clipboard.setData(ClipboardData(text: value));
}
