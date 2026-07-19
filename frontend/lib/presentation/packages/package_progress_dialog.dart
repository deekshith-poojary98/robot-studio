import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';

Future<void> showPackageProgressDialog(
  BuildContext context, {
  required String title,
  required String packageName,
  required Future<PackageOperationResult> Function() operation,
  required ValueChanged<PackageOperationResult> onSuccess,
  required ValueChanged<Object> onError,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PackageProgressDialog(
      title: title,
      packageName: packageName,
      operation: operation,
      onSuccess: onSuccess,
      onError: onError,
    ),
  );
}

class _PackageProgressDialog extends StatefulWidget {
  const _PackageProgressDialog({
    required this.title,
    required this.packageName,
    required this.operation,
    required this.onSuccess,
    required this.onError,
  });

  final String title;
  final String packageName;
  final Future<PackageOperationResult> Function() operation;
  final ValueChanged<PackageOperationResult> onSuccess;
  final ValueChanged<Object> onError;

  @override
  State<_PackageProgressDialog> createState() => _PackageProgressDialogState();
}

class _PackageProgressDialogState extends State<_PackageProgressDialog> {
  bool _running = true;
  String? _error;
  List<String> _logs = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await widget.operation();
      if (!mounted) return;
      setState(() {
        _running = false;
        _logs = result.logs;
      });
      widget.onSuccess(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
      });
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.packageName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                'Working…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ] else ...[
              Text(
                'Completed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_logs.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _logs[index],
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontFamily: 'Menlo',
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (!_running)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}
