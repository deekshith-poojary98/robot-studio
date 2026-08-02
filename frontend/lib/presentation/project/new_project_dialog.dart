import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Asks only for a project name (project location comes from the open workspace).
Future<String?> showNewProjectDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const NewProjectDialog(),
  );
}

/// Asks for a name plus the parent folder the project is created in.
Future<({String name, String location})?> showNewStandaloneProjectDialog(
  BuildContext context, {
  String? initialLocation,
}) {
  return showDialog<({String name, String location})>(
    context: context,
    builder: (context) => NewProjectDialog(
      askLocation: true,
      initialLocation: initialLocation,
    ),
  );
}

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({
    super.key,
    this.askLocation = false,
    this.initialLocation,
  });

  /// When true the dialog collects a parent folder and pops a
  /// `(name, location)` record instead of just the name.
  final bool askLocation;
  final String? initialLocation;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _nameController = TextEditingController();
  late final TextEditingController _locationController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController(
      text: widget.initialLocation ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose parent folder for the new project',
      );
      if (!mounted) return;
      if (selected != null) {
        setState(() {
          _locationController.text = selected;
          _error = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open folder picker: $error';
      });
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Project name is required');
      return;
    }
    if (!widget.askLocation) {
      Navigator.of(context).pop(name);
      return;
    }
    final location = _locationController.text.trim();
    if (location.isEmpty) {
      setState(() => _error = 'Choose where the project folder is created');
      return;
    }
    Navigator.of(context).pop((name: name, location: location));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text(
        'New Project',
        style: theme.textTheme.titleLarge,
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Project name',
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (_nameController.text.trim().isNotEmpty) {
                  _submit();
                }
              },
            ),
            if (widget.askLocation) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Location',
                          ),
                          onChanged: (_) => setState(() => _error = null),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'The project folder is created inside this location.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: _browse,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Browse…'),
                    ),
                  ),
                ],
              ),
            ],
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
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
