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
  final VoidCallback? onProblemsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: AppColors.statusBar,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Long project / file names shrink instead of overflowing the bar.
          _flexItem(projectName?.toUpperCase() ?? 'NO PROJECT', flex: 2),
          if (fileName != null) _flexItem(fileName!.toUpperCase(), flex: 3),
          if (cursorLabel != null) _item(cursorLabel!),
          if (dirty) _item('MODIFIED'),
          if (errorCount > 0)
            _clickableItem('ERRORS $errorCount', onProblemsTap),
          if (warningCount > 0)
            _clickableItem('WARNINGS $warningCount', onProblemsTap),
          _item('UTF-8'),
          _item('LF'),
          const Spacer(),
          if (robotVersion != null && robotVersion!.isNotEmpty)
            _item('ROBOT $robotVersion'),
          if (pythonVersion != null && pythonVersion!.isNotEmpty)
            _item('PYTHON $pythonVersion'),
        ],
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: AppColors.statusBarText,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  Widget _item(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Text(label, style: _labelStyle),
    );
  }

  Widget _flexItem(String label, {required int flex}) {
    return Flexible(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _labelStyle,
        ),
      ),
    );
  }

  Widget _clickableItem(String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
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
  }
}
