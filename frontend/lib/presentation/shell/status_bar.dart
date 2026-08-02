import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    this.projectName,
    this.fileName,
    this.cursorLabel,
    this.dirty = false,
    this.errorCount = 0,
    this.warningCount = 0,
    this.robotVersion,
    this.pythonVersion,
    this.notification,
    this.backendUnavailable = false,
    this.onProblemsTap,
  });

  final String? projectName;
  final String? fileName;
  final String? cursorLabel;
  final bool dirty;
  final int errorCount;
  final int warningCount;
  final String? robotVersion;
  final String? pythonVersion;
  final String? notification;
  final bool backendUnavailable;
  final VoidCallback? onProblemsTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Status bar',
      child: Container(
        height: 24,
        decoration: const BoxDecoration(
          color: AppColors.statusBar,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _flexItem(
                    projectName?.toUpperCase() ?? 'NO PROJECT',
                    flex: 2,
                    tooltip: projectName == null
                        ? 'No project open'
                        : projectName!,
                  ),
                  if (fileName != null)
                    _flexItem(
                      fileName!.toUpperCase(),
                      flex: 3,
                      tooltip: fileName,
                    ),
                  if (cursorLabel != null)
                    _item(cursorLabel!, tooltip: 'Cursor position'),
                  if (dirty) _item('MODIFIED', tooltip: 'Unsaved changes'),
                  if (errorCount > 0)
                    _clickableItem(
                      'ERRORS $errorCount',
                      onProblemsTap,
                      tooltip: 'Open Problems panel',
                    ),
                  if (warningCount > 0)
                    _clickableItem(
                      'WARNINGS $warningCount',
                      onProblemsTap,
                      tooltip: 'Open Problems panel',
                    ),
                  if (notification != null && notification!.isNotEmpty)
                    _flexItem(notification!, flex: 3, tooltip: notification),
                ],
              ),
            ),
            if (robotVersion != null && robotVersion!.isNotEmpty)
              _item(
                'ROBOT $robotVersion',
                tooltip: 'Robot Framework version',
                trailing: false,
              ),
            if (pythonVersion != null && pythonVersion!.isNotEmpty)
              _item(
                'PYTHON $pythonVersion',
                tooltip: 'Python version',
                trailing: false,
              ),
            if (backendUnavailable)
              _item(
                'BACKEND UNAVAILABLE',
                tooltip:
                    'Start the backend with: python -m robot_studio.main',
                trailing: false,
              ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: AppColors.statusBarText,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  Widget _item(String label, {String? tooltip, bool trailing = true}) {
    final child = Padding(
      padding: trailing
          ? const EdgeInsets.only(right: AppSpacing.md)
          : const EdgeInsets.only(left: AppSpacing.md),
      child: Text(label, style: _labelStyle),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip, child: child);
  }

  Widget _flexItem(String label, {required int flex, String? tooltip}) {
    return Flexible(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: tooltip == null
            ? Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle,
              )
            : Tooltip(
                message: tooltip,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle,
                ),
              ),
      ),
    );
  }

  Widget _clickableItem(
    String label,
    VoidCallback? onTap, {
    String? tooltip,
  }) {
    final child = Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.statusBarText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.statusBarText,
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip, child: child);
  }
}
