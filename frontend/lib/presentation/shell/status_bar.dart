import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.backendConnected,
    this.backendVersion,
    this.workspaceName,
    this.fileName,
    this.cursorLabel,
    this.dirty = false,
    this.errorCount = 0,
    this.warningCount = 0,
    this.robotVersion,
    this.pythonVersion,
    this.venvName,
  });

  final bool backendConnected;
  final String? backendVersion;
  final String? workspaceName;
  final String? fileName;
  final String? cursorLabel;
  final bool dirty;
  final int errorCount;
  final int warningCount;
  final String? robotVersion;
  final String? pythonVersion;
  final String? venvName;

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
          if (fileName != null) _item(fileName!.toUpperCase()),
          if (cursorLabel != null) _item(cursorLabel!),
          if (dirty) _item('MODIFIED'),
          if (errorCount > 0) _item('ERRORS $errorCount'),
          if (warningCount > 0) _item('WARNINGS $warningCount'),
          _item('UTF-8'),
          _item('LF'),
          const Spacer(),
          if (backendVersion != null) _item('API v$backendVersion'),
          _item(
            robotVersion != null && robotVersion!.isNotEmpty
                ? 'ROBOT $robotVersion'
                : 'ROBOT —',
          ),
          _item(
            pythonVersion != null && pythonVersion!.isNotEmpty
                ? 'PYTHON $pythonVersion'
                : 'PYTHON —',
          ),
          _item(
            venvName != null && venvName!.isNotEmpty
                ? 'VENV $venvName'
                : 'VENV —',
          ),
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
