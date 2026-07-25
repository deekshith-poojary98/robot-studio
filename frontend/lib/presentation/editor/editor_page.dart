import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import 'document_outline.dart';
import 'editor_navigation_widgets.dart';
import 'editor_tabs_bar.dart';
import 'robot_code_editor.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.tabs,
    required this.activePath,
    required this.outline,
    required this.isLoadingOutline,
    required this.wordWrap,
    required this.hover,
    required this.references,
    required this.statusMessage,
    required this.breadcrumb,
    required this.completionItems,
    required this.diagnostics,
    required this.signatureHelp,
    required this.peekDefinition,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onContentChanged,
    required this.onSave,
    required this.onSaveAll,
    required this.onToggleWordWrap,
    required this.onGoToDefinition,
    required this.onPeekDefinition,
    required this.onFindReferences,
    required this.onHover,
    required this.onOutlineSelect,
    required this.onFind,
    required this.onReplace,
    required this.onReveal,
    required this.onFormatDocument,
    required this.onFormatSelection,
    required this.onOpenSymbol,
    required this.onWorkspaceSymbol,
    required this.onCtrlClick,
    required this.onClosePeek,
    required this.onCursorChanged,
    this.jumpToLine,
    this.jumpToColumn,
  });

  final List<EditorTabInfo> tabs;
  final String? activePath;
  final List<IndexedSymbolInfo> outline;
  final bool isLoadingOutline;
  final bool wordWrap;
  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final String? statusMessage;
  final EditorBreadcrumbInfo breadcrumb;
  final List<CompletionItemInfo> completionItems;
  final List<DiagnosticInfo> diagnostics;
  final SignatureHelpInfo? signatureHelp;
  final IndexedSymbolInfo? peekDefinition;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final void Function(String path, String content) onContentChanged;
  final VoidCallback onSave;
  final VoidCallback onSaveAll;
  final VoidCallback onToggleWordWrap;
  final VoidCallback onGoToDefinition;
  final VoidCallback onPeekDefinition;
  final VoidCallback onFindReferences;
  final VoidCallback onHover;
  final ValueChanged<IndexedSymbolInfo> onOutlineSelect;
  final VoidCallback onFind;
  final VoidCallback onReplace;
  final VoidCallback onReveal;
  final VoidCallback onFormatDocument;
  final VoidCallback onFormatSelection;
  final VoidCallback onOpenSymbol;
  final VoidCallback onWorkspaceSymbol;
  final VoidCallback onCtrlClick;
  final VoidCallback onClosePeek;
  final void Function(int line, int column) onCursorChanged;
  final int? jumpToLine;
  final int? jumpToColumn;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _editorKey = GlobalKey<RobotCodeEditorState>();

  EditorTabInfo? get _active {
    final path = widget.activePath;
    if (path == null) return null;
    for (final tab in widget.tabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  void _handleFind() {
    _editorKey.currentState?.showFind();
    widget.onFind();
  }

  void _handleReplace() {
    _editorKey.currentState?.showFind(replace: true);
    widget.onReplace();
  }

  void _handleFormatSelection() {
    widget.onFormatSelection();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          EditorTabsBar(
            tabs: widget.tabs,
            activePath: widget.activePath,
            onSelect: widget.onSelectTab,
            onClose: widget.onCloseTab,
          ),
          EditorBreadcrumbBar(breadcrumb: widget.breadcrumb),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                _EditorAction(
                  buttonKey: const Key('editor.save'),
                  icon: Icons.save_outlined,
                  label: 'Save',
                  onPressed: active == null ? null : widget.onSave,
                ),
                _EditorAction(
                  buttonKey: const Key('editor.save-all'),
                  icon: Icons.save_as_outlined,
                  label: 'Save All',
                  onPressed: widget.tabs.isEmpty ? null : widget.onSaveAll,
                ),
                _EditorAction(
                  buttonKey: const Key('editor.format'),
                  icon: Icons.format_align_left,
                  label: 'Format',
                  onPressed: active == null ? null : widget.onFormatDocument,
                ),
                _EditorAction(
                  buttonKey: const Key('editor.find'),
                  icon: Icons.search,
                  label: 'Find',
                  onPressed: active == null ? null : _handleFind,
                ),
                const Spacer(),
                _WrapToggle(
                  wordWrap: widget.wordWrap,
                  onToggle: widget.onToggleWordWrap,
                ),
                const SizedBox(width: 4),
                _EditorOverflowMenu(
                  hasActiveFile: active != null,
                  onReplace: _handleReplace,
                  onFormatSelection: _handleFormatSelection,
                  onGoToDefinition: widget.onGoToDefinition,
                  onPeekDefinition: widget.onPeekDefinition,
                  onFindReferences: widget.onFindReferences,
                  onHover: widget.onHover,
                  onOpenSymbol: widget.onOpenSymbol,
                  onWorkspaceSymbol: widget.onWorkspaceSymbol,
                  onReveal: widget.onReveal,
                ),
              ],
            ),
          ),
          if (widget.statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.accentSoft,
              child: Text(
                widget.statusMessage!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: active == null
                ? const EmptyState(
                    icon: Icons.description_outlined,
                    title: 'No file open',
                    message:
                        'Pick a .robot file in the Explorer, or press the '
                        'search box in the toolbar to jump to one.',
                  )
                : Row(
                    children: [
                      Expanded(
                        child: RobotCodeEditor(
                          key: _editorKey,
                          path: active.path,
                          initialContent: active.content,
                          wordWrap: widget.wordWrap,
                          jumpToLine: widget.jumpToLine,
                          jumpToColumn: widget.jumpToColumn,
                          completionItems: widget.completionItems,
                          diagnostics: widget.diagnostics,
                          signatureHelp: widget.signatureHelp,
                          peekDefinition: widget.peekDefinition,
                          onClosePeek: widget.onClosePeek,
                          onCtrlClick: widget.onCtrlClick,
                          onContentChanged: (content) =>
                              widget.onContentChanged(active.path, content),
                          onCursorChanged: widget.onCursorChanged,
                        ),
                      ),
                      DocumentOutlinePanel(
                        symbols: widget.outline,
                        isLoading: widget.isLoadingOutline,
                        onSelect: widget.onOutlineSelect,
                      ),
                      if (widget.hover != null || widget.references.isNotEmpty)
                        SizedBox(
                          width: 260,
                          child: _LanguageSidePanel(
                            hover: widget.hover,
                            references: widget.references,
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

/// Compact icon action for the editor strip. Editing verbs only.
class _EditorAction extends StatelessWidget {
  const _EditorAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
    );
  }
}

class _WrapToggle extends StatelessWidget {
  const _WrapToggle({required this.wordWrap, required this.onToggle});

  final bool wordWrap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('editor.wrap'),
      onPressed: onToggle,
      tooltip: wordWrap ? 'Word wrap: on' : 'Word wrap: off',
      icon: Icon(
        Icons.wrap_text,
        size: 16,
        color: wordWrap ? AppColors.accent : AppColors.textMuted,
      ),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
    );
  }
}

/// Language navigation lives here instead of the permanent strip, matching how
/// VS Code / PyCharm keep Definition, Peek, and References out of the chrome.
class _EditorOverflowMenu extends StatelessWidget {
  const _EditorOverflowMenu({
    required this.hasActiveFile,
    required this.onReplace,
    required this.onFormatSelection,
    required this.onGoToDefinition,
    required this.onPeekDefinition,
    required this.onFindReferences,
    required this.onHover,
    required this.onOpenSymbol,
    required this.onWorkspaceSymbol,
    required this.onReveal,
  });

  final bool hasActiveFile;
  final VoidCallback onReplace;
  final VoidCallback onFormatSelection;
  final VoidCallback onGoToDefinition;
  final VoidCallback onPeekDefinition;
  final VoidCallback onFindReferences;
  final VoidCallback onHover;
  final VoidCallback onOpenSymbol;
  final VoidCallback onWorkspaceSymbol;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('editor.more'),
      tooltip: 'More editor actions',
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_horiz, size: 16),
      iconSize: 16,
      onSelected: (value) => switch (value) {
        'replace' => onReplace(),
        'format-selection' => onFormatSelection(),
        'definition' => onGoToDefinition(),
        'peek' => onPeekDefinition(),
        'references' => onFindReferences(),
        'hover' => onHover(),
        'open-symbol' => onOpenSymbol(),
        'project-symbol' => onWorkspaceSymbol(),
        'reveal' => onReveal(),
        _ => null,
      },
      itemBuilder: (context) => [
        _item('replace', Icons.find_replace, 'Replace…', hasActiveFile),
        _item(
          'format-selection',
          Icons.format_indent_increase,
          'Format Selection',
          hasActiveFile,
        ),
        const PopupMenuDivider(),
        _item(
          'definition',
          Icons.subdirectory_arrow_right,
          'Go to Definition',
          hasActiveFile,
        ),
        _item(
          'peek',
          Icons.visibility_outlined,
          'Peek Definition',
          hasActiveFile,
        ),
        _item('references', Icons.link, 'Find References', hasActiveFile),
        _item('hover', Icons.info_outline, 'Show Hover Info', hasActiveFile),
        const PopupMenuDivider(),
        _item(
          'open-symbol',
          Icons.list_alt,
          'Go to Symbol in File',
          hasActiveFile,
        ),
        _item(
          'project-symbol',
          Icons.travel_explore,
          'Find Symbol in Project',
          true,
        ),
        const PopupMenuDivider(),
        _item('reveal', Icons.folder_open, 'Reveal in Folder', hasActiveFile),
      ],
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    bool enabled,
  ) {
    return PopupMenuItem<String>(
      key: Key('editor.menu.$value'),
      value: value,
      enabled: enabled,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 16),
        title: Text(label),
      ),
    );
  }
}

class _LanguageSidePanel extends StatelessWidget {
  const _LanguageSidePanel({required this.hover, required this.references});

  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (hover != null) ...[
            Text('Hover', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('${hover!.kind.label}: ${hover!.name}'),
            Text(
              '${hover!.filePath}:${hover!.line}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (hover!.documentation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(hover!.documentation),
            ],
            const SizedBox(height: 14),
          ],
          if (references.isNotEmpty) ...[
            Text('References', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...references.map(
              (ref) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ref.filePath}:${ref.line}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (ref.context.isNotEmpty)
                      Text(
                        ref.context,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
