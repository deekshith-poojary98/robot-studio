import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

Future<({String name, String url})?> showAddGitRemoteDialog(
  BuildContext context, {
  String initialName = 'origin',
  String initialUrl = '',
}) {
  return showDialog<({String name, String url})>(
    context: context,
    builder: (context) =>
        _AddGitRemoteDialog(initialName: initialName, initialUrl: initialUrl),
  );
}

class _AddGitRemoteDialog extends StatefulWidget {
  const _AddGitRemoteDialog({
    required this.initialName,
    required this.initialUrl,
  });

  final String initialName;
  final String initialUrl;

  @override
  State<_AddGitRemoteDialog> createState() => _AddGitRemoteDialogState();
}

class _AddGitRemoteDialogState extends State<_AddGitRemoteDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Remote name is required.');
      return;
    }
    if (url.isEmpty) {
      setState(() => _error = 'Remote URL is required.');
      return;
    }
    Navigator.of(context).pop((name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text('Add remote', style: Theme.of(context).textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connect this repository to GitHub, GitLab, or another host, then Push.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'origin',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _urlController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://github.com/org/repo.git',
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: palette.error, fontSize: 12),
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
          style: FilledButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Add remote'),
        ),
      ],
    );
  }
}
