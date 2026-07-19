import 'package:flutter/material.dart';

import '../../core/gateway/models/execution_info.dart';
import '../../core/theme/app_theme.dart';
import 'execution_console.dart';
import 'execution_history_list.dart';

class ExecutionPage extends StatelessWidget {
  const ExecutionPage({
    super.key,
    required this.consoleLines,
    required this.history,
    required this.isLoadingHistory,
    required this.status,
    required this.currentRun,
    required this.elapsedLabel,
    this.onRefreshHistory,
    this.onRunFile,
    this.onRunProject,
    this.onStop,
  });

  final List<String> consoleLines;
  final List<ExecutionInfo> history;
  final bool isLoadingHistory;
  final ExecutionStatus status;
  final ExecutionInfo? currentRun;
  final String elapsedLabel;
  final VoidCallback? onRefreshHistory;
  final VoidCallback? onRunFile;
  final VoidCallback? onRunProject;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final running = status.isActive;
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Execution',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        running
                            ? 'Running · $elapsedLabel'
                            : 'Status: ${status.label}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: running ? null : onRunFile,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run File'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: running ? null : onRunProject,
                  icon: const Icon(Icons.playlist_play, size: 16),
                  label: const Text('Run Project'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: running ? onStop : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ),
          if (currentRun != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                currentRun!.suite,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ColoredBox(
                    color: AppColors.rail,
                    child: ExecutionConsole(lines: consoleLines),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: ExecutionHistoryList(
                    runs: history,
                    isLoading: isLoadingHistory,
                    onRefresh: onRefreshHistory,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
