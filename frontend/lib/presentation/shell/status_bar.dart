import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.backendConnected,
    this.backendVersion,
    this.workspaceName,
  });

  final bool backendConnected;
  final String? backendVersion;
  final String? workspaceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: AppColors.statusBar,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _item(backendConnected ? 'READY' : 'OFFLINE'),
          _item(workspaceName?.toUpperCase() ?? 'NO WORKSPACE'),
          _item('UTF-8'),
          _item('LF'),
          const Spacer(),
          if (backendVersion != null) _item('API v$backendVersion'),
          _item('ROBOT —'),
          _item('PYTHON —'),
          _item('VENV —'),
        ],
      ),
    );
  }

  Widget _item(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.statusBarText,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
