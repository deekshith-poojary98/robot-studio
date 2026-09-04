import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/git_info.dart';
import '../../core/theme/app_theme.dart';
import '../git/history_panel.dart';
import '../workspace/explorer_file_actions.dart';
import 'empty_state.dart';
import 'explorer_file_icon.dart';
import 'explorer_tree.dart';
import 'app_menu.dart';
import 'app_toast.dart';

enum _InlineEditKind { rename, newFile, newFolder }

/// Shared [TapRegion.groupId] for the explorer tree and its header actions
/// (New File / New Folder). Taps inside the group do not clear selection.
const Object kExplorerFileTreeTapGroup = #explorerFileTree;

class _InlineEdit {
  const _InlineEdit({
    required this.kind,
    required this.parentPath,
    this.targetPath,
    this.initialName = '',
  });

  final _InlineEditKind kind;
  final String parentPath;
  final String? targetPath;
  final String initialName;
}

/// VS Code-style virtualized file tree: only visible rows are built.
/// Tree data comes from [EditorShellController] via [rows]; mutations flow
/// through gateway callbacks → EventBus → live events (no local full reload).
class VirtualFileTree extends StatefulWidget {
  const VirtualFileTree({
    super.key,
    required this.rows,
    required this.onOpenFile,
    required this.onToggleDirectory,
    this.gitFileStatuses = const {},
    this.isLoading = false,
    this.emptyMessage = 'No files found.',
    this.emptyHint,
    this.selectedPath,
    this.rootPath,
    this.onEnsureExpanded,
    this.onCreateEntry,
    this.onRenameEntry,
    this.onDeleteEntry,
    this.onDuplicateEntry,
    this.onMoveEntry,
    this.onCopyRelativePath,
    this.onCopyAbsolutePath,
    this.onRevealInOs,
  });

  final List<FlatFileTreeRow> rows;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onToggleDirectory;
  final Map<String, GitFileStatus> gitFileStatuses;
  final bool isLoading;
  final String emptyMessage;
  final String? emptyHint;
  final String? selectedPath;
  final String? rootPath;
  final Future<void> Function(String path)? onEnsureExpanded;
  final Future<void> Function({
    required String parentPath,
    required String name,
    required bool isDirectory,
  })?
  onCreateEntry;
  final Future<void> Function({required String path, required String newName})?
  onRenameEntry;
  final Future<void> Function(List<String> paths)? onDeleteEntry;
  final Future<void> Function(String path)? onDuplicateEntry;
  final Future<void> Function({
    required List<String> sourcePaths,
    required String destinationParentPath,
  })?
  onMoveEntry;
  final ValueChanged<List<String>>? onCopyRelativePath;
  final ValueChanged<List<String>>? onCopyAbsolutePath;
  final ValueChanged<String>? onRevealInOs;

  @override
  State<VirtualFileTree> createState() => VirtualFileTreeState();
}

class VirtualFileTreeState extends State<VirtualFileTree> {
  _InlineEdit? _edit;
  String? _selectedPath;
  final Set<String> _selectedPaths = {};
  String? _anchorPath;
  String _draftName = '';
  final FocusNode _focusNode = FocusNode(debugLabel: 'explorer-file-tree');

  static const double rowHeight = 26;

  @override
  void initState() {
    super.initState();
    _syncSelectionFromExternal(widget.selectedPath);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VirtualFileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPath != oldWidget.selectedPath) {
      _syncSelectionFromExternal(widget.selectedPath);
    }
  }

  void _syncSelectionFromExternal(String? path) {
    _selectedPath = path;
    _selectedPaths
      ..clear()
      ..addAll(path == null || path.isEmpty ? const <String>[] : [path]);
    _anchorPath = path;
  }

  void _selectOnly(String path) {
    _selectedPath = path;
    _selectedPaths
      ..clear()
      ..add(path);
    _anchorPath = path;
  }

  void _clearSelection() {
    if (_selectedPaths.isEmpty && _selectedPath == null) return;
    setState(() {
      _selectedPaths.clear();
      _selectedPath = null;
      _anchorPath = null;
    });
  }

  void _clearSelectionOnBlankOrOutsideTap() {
    // VS Code-style: blank explorer space / click outside the explorer chrome
    // clears the create target so New File lands at the project root.
    // The open editor path can still soft-highlight via [widget.selectedPath].
    _clearSelection();
  }

  void _toggleInSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
      if (_selectedPath == path) {
        _selectedPath = _selectedPaths.isEmpty ? null : _selectedPaths.first;
      }
    } else {
      _selectedPaths.add(path);
      _selectedPath = path;
    }
    _anchorPath = path;
  }

  void _selectRangeTo(String path) {
    final rows = widget.rows;
    if (rows.isEmpty) {
      _selectOnly(path);
      return;
    }
    final anchor = _anchorPath ?? _selectedPath ?? path;
    final start = rows.indexWhere((row) => row.node.path == anchor);
    final end = rows.indexWhere((row) => row.node.path == path);
    if (start < 0 || end < 0) {
      _selectOnly(path);
      return;
    }
    final low = start < end ? start : end;
    final high = start < end ? end : start;
    _selectedPaths
      ..clear()
      ..addAll([for (var i = low; i <= high; i++) rows[i].node.path]);
    _selectedPath = path;
  }

  List<String> _orderedSelection() {
    final selected = _selectedPaths.toSet();
    final ordered = <String>[
      for (final row in widget.rows)
        if (selected.contains(row.node.path)) row.node.path,
    ];
    for (final path in selected) {
      if (!ordered.contains(path)) ordered.add(path);
    }
    return ordered;
  }

  List<String> _operationTargets({String? fallback}) {
    final ordered = _orderedSelection();
    if (ordered.isNotEmpty) {
      return ExplorerFileActions.pruneNestedPaths(ordered);
    }
    if (fallback != null && fallback.isNotEmpty) return [fallback];
    return const [];
  }

  bool _isPrimaryModifierPressed() {
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final control = HardwareKeyboard.instance.isControlPressed;
    return defaultTargetPlatform == TargetPlatform.macOS ? meta : control;
  }

  void _handlePrimaryTap(FlatFileTreeRow row) {
    final path = row.node.path;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final modifier = _isPrimaryModifierPressed();
    setState(() {
      if (shift) {
        _selectRangeTo(path);
      } else if (modifier) {
        _toggleInSelection(path);
      } else {
        _selectOnly(path);
      }
    });
    if (shift || modifier) return;
    if (row.node.isDir) {
      widget.onToggleDirectory(path);
    } else {
      widget.onOpenFile(path);
    }
  }

  void _prepareContextSelection(String path) {
    if (!_selectedPaths.contains(path)) {
      _selectOnly(path);
    } else {
      _selectedPath = path;
    }
  }

  void beginNewFile([String? parentPath]) {
    final parent = parentPath ?? _selectedDirectoryOrRoot();
    unawaited(_startCreate(parent, isDirectory: false));
  }

  void beginNewFolder([String? parentPath]) {
    final parent = parentPath ?? _selectedDirectoryOrRoot();
    unawaited(_startCreate(parent, isDirectory: true));
  }

  void beginRename([String? path]) {
    final target = path ?? _selectedPath;
    if (target == null) return;
    if (widget.rootPath != null &&
        target.replaceAll('\\', '/') ==
            widget.rootPath!.replaceAll('\\', '/')) {
      return;
    }
    final parent = ExplorerFileActions.parentPath(target);
    final name = ExplorerFileActions.basename(target);
    setState(() {
      _selectOnly(target);
      _edit = _InlineEdit(
        kind: _InlineEditKind.rename,
        parentPath: parent,
        targetPath: target,
        initialName: name,
      );
      _draftName = name;
    });
  }

  Future<void> deleteSelected() async {
    final targets = _operationTargets();
    if (targets.isEmpty) return;
    await widget.onDeleteEntry?.call(targets);
  }

  Future<void> _startCreate(String parent, {required bool isDirectory}) async {
    await widget.onEnsureExpanded?.call(parent);
    if (!mounted) return;
    setState(() {
      _edit = _InlineEdit(
        kind: isDirectory ? _InlineEditKind.newFolder : _InlineEditKind.newFile,
        parentPath: parent,
        initialName: '',
      );
      _draftName = '';
    });
  }

  String _selectedDirectoryOrRoot() {
    final root = widget.rootPath ?? '';
    final selected = _selectedPath;
    if (selected == null || selected.isEmpty) return root;
    for (final row in widget.rows) {
      if (row.node.path == selected) {
        return row.node.isDir
            ? selected
            : ExplorerFileActions.parentPath(selected);
      }
    }
    return ExplorerFileActions.parentPath(selected);
  }

  List<String> _siblingNames(String parentPath, {String? excluding}) {
    final parent = parentPath.replaceAll('\\', '/');
    final root = widget.rootPath?.replaceAll('\\', '/');
    final names = <String>[];
    for (final row in widget.rows) {
      final path = row.node.path.replaceAll('\\', '/');
      if (excluding != null && path == excluding.replaceAll('\\', '/')) {
        continue;
      }
      final rowParent = ExplorerFileActions.parentPath(path);
      final atRoot =
          root != null && (parent == root || parent.isEmpty) && row.depth == 0;
      if (atRoot || rowParent.replaceAll('\\', '/') == parent) {
        names.add(row.node.name);
      }
    }
    return names;
  }

  Future<void> _showContextMenu(
    TapDownDetails details,
    FlatFileTreeRow row,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final revealLabel = ExplorerFileActions.revealLabel();
    final isDir = row.node.isDir;

    setState(() => _prepareContextSelection(row.node.path));
    final targets = _operationTargets(fallback: row.node.path);
    final multi = targets.length > 1;

    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (!multi && !isDir)
          const AppPopupMenuItem(value: 'open', child: Text('Open')),
        if (!multi && isDir) ...[
          const AppPopupMenuItem(value: 'new_file', child: Text('New File')),
          const AppPopupMenuItem(
            value: 'new_folder',
            child: Text('New Folder'),
          ),
          const AppPopupMenuDivider(),
        ],
        if (!multi)
          const AppPopupMenuItem(value: 'rename', child: Text('Rename')),
        if (!multi && !isDir)
          const AppPopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        AppPopupMenuItem(
          value: 'delete',
          child: Text(multi ? 'Delete ${targets.length} Items' : 'Delete'),
        ),
        const AppPopupMenuDivider(),
        AppPopupMenuItem(
          value: 'copy_rel',
          child: Text(multi ? 'Copy Relative Paths' : 'Copy Relative Path'),
        ),
        AppPopupMenuItem(
          value: 'copy_abs',
          child: Text(multi ? 'Copy Absolute Paths' : 'Copy Absolute Path'),
        ),
        if (!multi) AppPopupMenuItem(value: 'reveal', child: Text(revealLabel)),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'open':
        widget.onOpenFile(row.node.path);
      case 'new_file':
        beginNewFile(row.node.path);
      case 'new_folder':
        beginNewFolder(row.node.path);
      case 'rename':
        beginRename(row.node.path);
      case 'duplicate':
        await widget.onDuplicateEntry?.call(row.node.path);
      case 'delete':
        await widget.onDeleteEntry?.call(targets);
      case 'copy_rel':
        widget.onCopyRelativePath?.call(targets);
      case 'copy_abs':
        widget.onCopyAbsolutePath?.call(targets);
      case 'reveal':
        widget.onRevealInOs?.call(row.node.path);
    }
  }

  Future<void> _commitEdit(String rawName) async {
    final edit = _edit;
    if (edit == null) return;
    var name = rawName.trim();
    if (edit.kind == _InlineEditKind.newFile) {
      final withRobot = ExplorerFileActions.robotSuggestion(name);
      if (withRobot != null) name = withRobot;
    }

    // Rename → same name is a no-op (don't treat the current entry as a clash).
    if (edit.kind == _InlineEditKind.rename && edit.targetPath != null) {
      final current = ExplorerFileActions.basename(edit.targetPath!);
      if (name == current) {
        setState(() => _edit = null);
        return;
      }
    }

    final error = ExplorerFileActions.validateName(
      name,
      existingNames: _siblingNames(edit.parentPath, excluding: edit.targetPath),
    );
    if (error != null) {
      if (mounted) {
        showAppToast(
          context,
          message: error,
          icon: Icons.error_outline,
          iconColor: context.palette.error,
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }
    setState(() => _edit = null);

    switch (edit.kind) {
      case _InlineEditKind.rename:
        if (edit.targetPath != null) {
          await widget.onRenameEntry?.call(
            path: edit.targetPath!,
            newName: name,
          );
        }
      case _InlineEditKind.newFile:
        await widget.onCreateEntry?.call(
          parentPath: edit.parentPath,
          name: name,
          isDirectory: false,
        );
      case _InlineEditKind.newFolder:
        await widget.onCreateEntry?.call(
          parentPath: edit.parentPath,
          name: name,
          isDirectory: true,
        );
    }
  }

  void _cancelEdit() {
    setState(() {
      _edit = null;
      _draftName = '';
    });
  }

  List<_DisplayRow> _displayRows() {
    final edit = _edit;
    final out = <_DisplayRow>[];
    var insertedCreate = false;
    final root = widget.rootPath?.replaceAll('\\', '/');

    bool isCreateParent(String path) {
      if (edit == null || edit.kind == _InlineEditKind.rename) return false;
      return path.replaceAll('\\', '/') ==
          edit.parentPath.replaceAll('\\', '/');
    }

    if (edit != null &&
        edit.kind != _InlineEditKind.rename &&
        root != null &&
        isCreateParent(root) &&
        widget.rows.isEmpty) {
      out.add(_DisplayRow.creating(edit, 0));
      return out;
    }

    for (var i = 0; i < widget.rows.length; i++) {
      final row = widget.rows[i];
      final path = row.node.path.replaceAll('\\', '/');

      if (edit != null &&
          edit.kind != _InlineEditKind.rename &&
          !insertedCreate) {
        final parent = ExplorerFileActions.parentPath(path);
        final createParent = edit.parentPath.replaceAll('\\', '/');
        final atRootCreate =
            root != null &&
            createParent == root &&
            row.depth == 0 &&
            out
                .where((r) => r.kind == _DisplayKind.entry && r.depth == 0)
                .isEmpty;
        final underParent =
            parent.replaceAll('\\', '/') == createParent &&
            widget.rows.any(
              (r) =>
                  r.node.path.replaceAll('\\', '/') == createParent &&
                  r.expanded,
            );
        if (atRootCreate || underParent) {
          out.add(_DisplayRow.creating(edit, row.depth));
          insertedCreate = true;
        }
      }

      final renaming =
          edit?.kind == _InlineEditKind.rename &&
          edit?.targetPath?.replaceAll('\\', '/') == path;
      out.add(_DisplayRow.entry(row, renaming));

      if (edit != null &&
          edit.kind != _InlineEditKind.rename &&
          !insertedCreate &&
          row.node.isDir &&
          row.expanded &&
          isCreateParent(row.node.path)) {
        final hasChild =
            i + 1 < widget.rows.length && widget.rows[i + 1].depth > row.depth;
        if (!hasChild) {
          out.add(_DisplayRow.creating(edit, row.depth + 1));
          insertedCreate = true;
        }
      }
    }

    if (edit != null &&
        edit.kind != _InlineEditKind.rename &&
        !insertedCreate &&
        root != null &&
        isCreateParent(root)) {
      out.add(_DisplayRow.creating(edit, 0));
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.rows.isEmpty && _edit == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (widget.rows.isEmpty && _edit == null) {
      return EmptyState(
        icon: Icons.folder_open_outlined,
        title: widget.emptyMessage,
        message: widget.emptyHint ?? 'Create a file to get started.',
        compact: true,
        actionLabel: widget.onCreateEntry == null ? null : 'New File',
        onAction: widget.onCreateEntry == null
            ? null
            : () => beginNewFile(widget.rootPath),
      );
    }

    final display = _displayRows();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!mounted) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        final modifier = _isPrimaryModifierPressed();

        if (key == LogicalKeyboardKey.f2) {
          beginRename();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) {
          // Delete only — Backspace alone is ignored to avoid fighting the
          // inline rename field (which won't be focused on this Focus node).
          if (key == LogicalKeyboardKey.delete) {
            unawaited(deleteSelected());
            return KeyEventResult.handled;
          }
        }
        if (key == LogicalKeyboardKey.keyN && modifier && shift) {
          beginNewFolder();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyN && modifier && !shift) {
          beginNewFile();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          if (_selectedPaths.isNotEmpty || _selectedPath != null) {
            _clearSelection();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: TapRegion(
        groupId: kExplorerFileTreeTapGroup,
        onTapOutside: (_) => _clearSelectionOnBlankOrOutsideTap(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _clearSelectionOnBlankOrOutsideTap,
          child: _buildTreeBody(display),
        ),
      ),
    );
  }

  Widget _buildTreeBody(List<_DisplayRow> display) {
    final list = ListView.builder(
      key: const Key('virtual-file-tree'),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: display.length,
      itemExtent: _edit == null ? rowHeight : null,
      itemBuilder: (context, index) {
        final item = display[index];
        if (item.kind == _DisplayKind.creating) {
          return _buildCreatingRow(item);
        }
        return _buildEntryRow(item.row!, item.editing);
      },
    );

    final root = widget.rootPath;
    if (widget.onMoveEntry == null || root == null || root.isEmpty) {
      return list;
    }

    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) => details.data.any(_canDropOnRoot),
      onAcceptWithDetails: (details) {
        final sources = ExplorerFileActions.pruneNestedPaths(
          details.data.where(_canDropOnRoot),
        );
        if (sources.isEmpty) return;
        widget.onMoveEntry?.call(
          sourcePaths: sources,
          destinationParentPath: root,
        );
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? context.palette.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: highlighted ? context.palette.accent : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: list,
        );
      },
    );
  }

  bool _canDropOnRoot(String sourcePath) {
    final root = widget.rootPath?.replaceAll('\\', '/');
    if (root == null || root.isEmpty) return false;
    final source = sourcePath.replaceAll('\\', '/');
    if (source == root) return false;
    if (root.startsWith('$source/')) return false;
    final parent = ExplorerFileActions.parentPath(source).replaceAll('\\', '/');
    // Already a direct child of the project root.
    if (parent == root) return false;
    return true;
  }

  Widget _buildCreatingRow(_DisplayRow item) {
    final edit = item.edit!;
    final isFolder = edit.kind == _InlineEditKind.newFolder;
    return ExplorerTreeItem(
      label: '',
      leading: explorerFileIcon(name: _draftName, isDirectory: isFolder),
      indent: item.depth,
      isEditing: true,
      editInitialValue: edit.initialName,
      editHint: isFolder ? 'Folder name' : 'File name',
      onEditChanged: (value) => setState(() => _draftName = value),
      onEditSubmit: (value) {
        _draftName = value;
        _commitEdit(value);
      },
      onEditCancel: _cancelEdit,
    );
  }

  Widget _buildEntryRow(FlatFileTreeRow row, bool editing) {
    final node = row.node;
    final selected =
        _selectedPaths.contains(node.path) ||
        (_selectedPaths.isEmpty &&
            (_selectedPath ?? widget.selectedPath) == node.path);
    // Robot extension is appended silently on New File commit when missing.

    Widget child;
    if (node.isDir) {
      final canExpand = node.hasChildren || row.expanded || row.loading;
      child = ExplorerTreeItem(
        leading: explorerFileIcon(
          name: node.name,
          isDirectory: true,
          expanded: row.expanded,
          loading: row.loading,
        ),
        label: node.name,
        indent: row.depth,
        selected: selected,
        tooltip: ExplorerFileActions.homeRelativePath(node.path),
        semanticLabel: 'Folder ${node.name}',
        isEditing: editing,
        editInitialValue: editing ? _edit?.initialName : null,
        onEditChanged: editing
            ? (value) => setState(() => _draftName = value)
            : null,
        onEditSubmit: editing
            ? (value) {
                _draftName = value;
                _commitEdit(value);
              }
            : null,
        onEditCancel: editing ? _cancelEdit : null,
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
                color: context.palette.textMuted,
              )
            : null,
        onTap: editing
            ? null
            : () {
                _focusNode.requestFocus();
                _handlePrimaryTap(row);
              },
        onSecondaryTap: editing
            ? null
            : (details) {
                _focusNode.requestFocus();
                _showContextMenu(details, row);
              },
      );
    } else {
      child = ExplorerTreeItem(
        leading: explorerFileIcon(name: node.name),
        label: node.name,
        indent: row.depth,
        selected: selected,
        tooltip: ExplorerFileActions.homeRelativePath(node.path),
        semanticLabel: 'File ${node.name}',
        isEditing: editing,
        editInitialValue: editing ? _edit?.initialName : null,
        onEditChanged: editing
            ? (value) => setState(() => _draftName = value)
            : null,
        onEditSubmit: editing
            ? (value) {
                _draftName = value;
                _commitEdit(value);
              }
            : null,
        onEditCancel: editing ? _cancelEdit : null,
        trailing: () {
          final status = _gitStatusFor(node);
          return status == null ? null : GitStatusBadge(status: status);
        }(),
        onTap: editing
            ? null
            : () {
                _focusNode.requestFocus();
                _handlePrimaryTap(row);
              },
        onSecondaryTap: editing
            ? null
            : (details) {
                _focusNode.requestFocus();
                _showContextMenu(details, row);
              },
      );
    }

    if (widget.onMoveEntry == null || editing) return child;

    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) {
        if (!node.isDir) return false;
        final dest = node.path.replaceAll('\\', '/');
        return details.data.any((sourcePath) {
          final source = sourcePath.replaceAll('\\', '/');
          if (source == dest) return false;
          if (dest.startsWith('$source/')) return false;
          final parent = ExplorerFileActions.parentPath(
            source,
          ).replaceAll('\\', '/');
          if (parent == dest) return false;
          return true;
        });
      },
      onAcceptWithDetails: (details) {
        final dest = node.path.replaceAll('\\', '/');
        final sources = ExplorerFileActions.pruneNestedPaths(
          details.data.where((sourcePath) {
            final source = sourcePath.replaceAll('\\', '/');
            if (source == dest) return false;
            if (dest.startsWith('$source/')) return false;
            final parent = ExplorerFileActions.parentPath(
              source,
            ).replaceAll('\\', '/');
            return parent != dest;
          }),
        );
        if (sources.isEmpty) return;
        widget.onMoveEntry?.call(
          sourcePaths: sources,
          destinationParentPath: node.path,
        );
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        final dragPaths = _selectedPaths.contains(node.path)
            ? _operationTargets(fallback: node.path)
            : [node.path];
        final dragCount = dragPaths.length;
        return Draggable<List<String>>(
          data: dragPaths,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: 220,
                child: ExplorerTreeItem(
                  label: dragCount > 1 ? '$dragCount items' : node.name,
                  leading: explorerFileIcon(
                    name: node.name,
                    isDirectory: node.isDir,
                  ),
                  selected: true,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: child),
          child: highlighted
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: context.palette.accent),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: child,
                )
              : child,
        );
      },
    );
  }

  GitFileStatus? _gitStatusFor(FileTreeNode node) {
    if (widget.gitFileStatuses.isEmpty) return null;
    final direct =
        widget.gitFileStatuses[node.relativePath] ??
        widget.gitFileStatuses[node.path];
    if (direct != null) return direct;
    final name = node.name;
    for (final entry in widget.gitFileStatuses.entries) {
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

enum _DisplayKind { entry, creating }

class _DisplayRow {
  const _DisplayRow._({
    required this.kind,
    this.row,
    this.edit,
    this.depth = 0,
    this.editing = false,
  });

  factory _DisplayRow.entry(FlatFileTreeRow row, bool editing) => _DisplayRow._(
    kind: _DisplayKind.entry,
    row: row,
    depth: row.depth,
    editing: editing,
  );

  factory _DisplayRow.creating(_InlineEdit edit, int depth) =>
      _DisplayRow._(kind: _DisplayKind.creating, edit: edit, depth: depth);

  final _DisplayKind kind;
  final FlatFileTreeRow? row;
  final _InlineEdit? edit;
  final int depth;
  final bool editing;
}
