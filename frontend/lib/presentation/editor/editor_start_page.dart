import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared empty-editor / project landing page.
class EditorStartPage extends StatelessWidget {
  const EditorStartPage({
    super.key,
    required this.title,
    required this.path,
    this.recentFiles = const [],
    this.onOpenFile,
    this.onOpenRecentFile,
    this.onSearchProject,
    this.onShowExplorer,
    this.explorerVisible = false,
    this.onManageEnvironments,
    this.onRunProject,
    this.onNewProject,
    this.onImportProject,
  });

  final String title;
  final String path;
  final List<String> recentFiles;
  final VoidCallback? onOpenFile;
  final ValueChanged<String>? onOpenRecentFile;
  final VoidCallback? onSearchProject;
  final VoidCallback? onShowExplorer;
  final bool explorerVisible;
  final VoidCallback? onManageEnvironments;
  final VoidCallback? onRunProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onImportProject;

  static String get _mod => Platform.isMacOS ? '⌘' : 'Ctrl+';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recent = recentFiles.take(3).toList();

    return Container(
      color: palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (path.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        SelectableText(
                          path,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildStart(context)),
                            const SizedBox(width: 48),
                            Expanded(child: _buildRecent(context, recent)),
                          ],
                        )
                      else ...[
                        _buildStart(context),
                        const SizedBox(height: 28),
                        _buildRecent(context, recent),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStart(BuildContext context) {
    return _Section(
      title: 'Start',
      child: Column(
        children: [
          if (onOpenFile != null)
            _ActionRow(
              label: 'Open File…',
              shortcut: '${_mod}P',
              onTap: onOpenFile!,
            ),
          if (onShowExplorer != null)
            _ActionRow(
              label: explorerVisible ? 'Hide Explorer' : 'Show Explorer',
              shortcut: '${_mod}B',
              onTap: onShowExplorer!,
            ),
          if (onSearchProject != null)
            _ActionRow(
              label: 'Search in Project',
              shortcut: '$_mod⇧F',
              onTap: onSearchProject!,
            ),
          if (onRunProject != null)
            _ActionRow(
              label: 'Run Project',
              shortcut: 'F5',
              onTap: onRunProject!,
            ),
          if (onManageEnvironments != null)
            _ActionRow(label: 'Environments', onTap: onManageEnvironments!),
          if (onNewProject != null)
            _ActionRow(label: 'New Project…', onTap: onNewProject!),
          if (onImportProject != null)
            _ActionRow(label: 'Import Project…', onTap: onImportProject!),
        ],
      ),
    );
  }

  Widget _buildRecent(BuildContext context, List<String> recent) {
    return _Section(
      title: 'Recent',
      child: recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'No recent files',
                style: TextStyle(
                  color: context.palette.textMuted,
                  fontSize: 12.5,
                ),
              ),
            )
          : Column(
              children: [
                for (final file in recent)
                  _ActionRow(
                    label: _basename(file),
                    detail: _displayPath(file),
                    onTap: onOpenRecentFile == null
                        ? null
                        : () => onOpenRecentFile!(file),
                  ),
              ],
            ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  static String _displayPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return normalized;
    return parts.sublist(parts.length - 3).join('/');
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.palette.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.label,
    this.shortcut,
    this.detail,
    this.onTap,
  });

  final String label;
  final String? shortcut;
  final String? detail;
  final VoidCallback? onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: _hovered && enabled
              ? palette.surfaceHover
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled
                              ? (_hovered
                                    ? palette.accent
                                    : palette.textPrimary)
                              : palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (widget.detail != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          widget.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.shortcut != null)
                  Text(
                    widget.shortcut!,
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
