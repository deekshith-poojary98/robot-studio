import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../git/history_panel.dart';
import 'explorer_tree.dart';

/// VS Code-style virtualized file tree: only visible rows are built.
class VirtualFileTree extends StatelessWidget {
  const VirtualFileTree({
    super.key,
    required this.rows,
    required this.onOpenFile,
    required this.onToggleDirectory,
    this.gitFileStatuses = const {},
    this.isLoading = false,
    this.emptyMessage = 'No files found.',
  });

  final List<FlatFileTreeRow> rows;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onToggleDirectory;
  final Map<String, GitFileStatus> gitFileStatuses;
  final bool isLoading;
  final String emptyMessage;

  static const double rowHeight = 28;

  @override
  Widget build(BuildContext context) {
    if (isLoading && rows.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.builder(
      key: const Key('virtual-file-tree'),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final node = row.node;
        if (node.isDir) {
          return _DirRow(
            row: row,
            onToggle: () => onToggleDirectory(node.path),
          );
        }
        return _FileRow(
          row: row,
          gitStatus: _gitStatusFor(node),
          onOpen: () => onOpenFile(node.path),
        );
      },
    );
  }

  GitFileStatus? _gitStatusFor(FileTreeNode node) {
    if (gitFileStatuses.isEmpty) return null;
    final direct = gitFileStatuses[node.relativePath] ?? gitFileStatuses[node.path];
    if (direct != null) return direct;
    final name = node.name;
    for (final entry in gitFileStatuses.entries) {
      final key = entry.key;
      if (key == name ||
          key.endsWith('/$name') ||
          node.path.endsWith('/$key')) {
        return entry.value;
      }
    }
    return null;
  }
}

class _DirRow extends StatelessWidget {
  const _DirRow({required this.row, required this.onToggle});

  final FlatFileTreeRow row;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final canExpand = node.hasChildren || row.expanded || row.loading;
    return ExplorerTreeItem(
      icon: row.loading
          ? Icons.hourglass_empty
          : row.expanded
              ? Icons.folder_open_outlined
              : Icons.folder_outlined,
      label: node.name,
      indent: row.depth,
      tooltip: node.path,
      trailing: row.loading
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : canExpand
              ? Icon(
                  row.expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 14,
                  color: AppColors.textMuted,
                )
              : null,
      onTap: onToggle,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.row,
    required this.onOpen,
    this.gitStatus,
  });

  final FlatFileTreeRow row;
  final VoidCallback onOpen;
  final GitFileStatus? gitStatus;

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    return ExplorerTreeItem(
      icon: _iconForSuffix(node.suffix),
      label: node.name,
      indent: row.depth,
      tooltip: node.path,
      trailing: gitStatus == null ? null : GitStatusBadge(status: gitStatus!),
      onTap: onOpen,
    );
  }

  IconData _iconForSuffix(String suffix) {
    return switch (suffix) {
      '.py' => Icons.code_outlined,
      '.resource' => Icons.library_books_outlined,
      '.robot' => Icons.description_outlined,
      '.md' => Icons.article_outlined,
      '.json' || '.yaml' || '.yml' || '.toml' => Icons.data_object_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}
