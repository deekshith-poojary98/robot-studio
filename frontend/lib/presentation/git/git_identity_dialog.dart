import 'package:flutter/material.dart';

import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';

Future<({String name, String email, String scope})?> showGitIdentityDialog(
  BuildContext context, {
  GitIdentityInfo? identity,
}) {
  return showDialog<({String name, String email, String scope})>(
    context: context,
    builder: (context) => _GitIdentityDialog(identity: identity),
  );
}

class _GitIdentityDialog extends StatefulWidget {
  const _GitIdentityDialog({this.identity});

  final GitIdentityInfo? identity;

  @override
  State<_GitIdentityDialog> createState() => _GitIdentityDialogState();
}

class _GitIdentityDialogState extends State<_GitIdentityDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late String _scope;
  String? _error;

  @override
  void initState() {
    super.initState();
    final identity = widget.identity;
    _nameController = TextEditingController(text: identity?.name ?? '');
    _emailController = TextEditingController(text: identity?.email ?? '');
    _scope = identity?.source == 'local' ? 'local' : 'global';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    Navigator.of(context).pop((name: name, email: email, scope: _scope));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final configured = widget.identity?.isComplete ?? false;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        configured ? 'Git identity' : 'Set Git identity',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Commits use this name and email as the author — not the project name.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Your name',
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Save for',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            RadioGroup<String>(
              groupValue: _scope,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _scope = value);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'global',
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All repositories on this machine'),
                    subtitle: Text(
                      'Writes Git user.name / user.email globally',
                      style: TextStyle(fontSize: 11, color: palette.textMuted),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'local',
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This repository only'),
                  ),
                ],
              ),
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
          child: Text(configured ? 'Save' : 'Save and continue'),
        ),
      ],
    );
  }
}
