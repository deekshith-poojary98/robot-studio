import 'package:flutter/foundation.dart';
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
    final palette = context.palette;
    return Semantics(
      container: true,
      label: 'Status bar',
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: palette.statusBar,
          border: Border(top: BorderSide(color: palette.borderSubtle)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _flexItem(
                    palette,
                    projectName?.toUpperCase() ?? 'NO PROJECT',
                    flex: 2,
                    tooltip: projectName == null
                        ? 'No project open'
                        : projectName!,
                  ),
                  if (fileName != null)
                    _flexItem(
                      palette,
                      fileName!.toUpperCase(),
                      flex: 3,
                      tooltip: fileName,
                    ),
                  if (cursorLabel != null)
                    _item(palette, cursorLabel!, tooltip: 'Cursor position'),
                  if (dirty)
                    _item(palette, 'MODIFIED', tooltip: 'Unsaved changes'),
                  if (errorCount > 0)
                    _clickableItem(
                      palette,
                      'ERRORS $errorCount',
                      onProblemsTap,
                      tooltip: 'Open Problems panel',
                    ),
                  if (warningCount > 0)
                    _clickableItem(
                      palette,
                      'WARNINGS $warningCount',
                      onProblemsTap,
                      tooltip: 'Open Problems panel',
                    ),
                  if (notification != null && notification!.isNotEmpty)
                    _flexItem(
                      palette,
                      notification!,
                      flex: 3,
                      tooltip: notification,
                    ),
                ],
              ),
            ),
            if (robotVersion != null && robotVersion!.isNotEmpty)
              _item(
                palette,
                'ROBOT $robotVersion',
                tooltip: 'Robot Framework version',
                trailing: false,
              ),
            if (pythonVersion != null && pythonVersion!.isNotEmpty)
              _item(
                palette,
                'PYTHON $pythonVersion',
                tooltip: 'Python version',
                trailing: false,
              ),
            if (backendUnavailable)
              _item(
                palette,
                'BACKEND UNAVAILABLE',
                tooltip: kReleaseMode
                    ? 'Robot Studio could not reach its backend service. '
                          'Quit and reopen the app, or reinstall.'
                    : 'Start the backend with: make backend',
                trailing: false,
              ),
          ],
        ),
      ),
    );
  }

  static TextStyle _labelStyle(AppPalette palette) => TextStyle(
    color: palette.statusBarText,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  Widget _item(
    AppPalette palette,
    String label, {
    String? tooltip,
    bool trailing = true,
  }) {
    final child = Padding(
      padding: trailing
          ? const EdgeInsets.only(right: AppSpacing.md)
          : const EdgeInsets.only(left: AppSpacing.md),
      child: Text(label, style: _labelStyle(palette)),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip, child: child);
  }

  Widget _flexItem(
    AppPalette palette,
    String label, {
    required int flex,
    String? tooltip,
  }) {
    return Flexible(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: tooltip == null
            ? Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(palette),
              )
            : Tooltip(
                message: tooltip,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(palette),
                ),
              ),
      ),
    );
  }

  Widget _clickableItem(
    AppPalette palette,
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
          style: TextStyle(
            color: palette.statusBarText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            decoration: TextDecoration.underline,
            decorationColor: palette.statusBarText,
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip, child: child);
  }
}
