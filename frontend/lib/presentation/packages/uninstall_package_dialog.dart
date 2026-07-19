import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';

Future<bool?> showUninstallPackageDialog(
  BuildContext context, {
  required PackageInfo package,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Uninstall Package'),
      content: Text('Uninstall "${package.name}" (${package.version})?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Uninstall'),
        ),
      ],
    ),
  );
}
