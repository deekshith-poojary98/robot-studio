import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
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
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: active == null ? null : widget.onSave,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save'),
                  ),
                  TextButton.icon(
                    onPressed: widget.tabs.isEmpty ? null : widget.onSaveAll,
                    icon: const Icon(Icons.save_as_outlined, size: 16),
                    label: const Text('Save All'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.format'),
                    onPressed: active == null ? null : widget.onFormatDocument,
                    icon: const Icon(Icons.format_align_left, size: 16),
                    label: const Text('Format'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.format-selection'),
                    onPressed: active == null ? null : _handleFormatSelection,
                    icon: const Icon(Icons.format_indent_increase, size: 16),
                    label: const Text('Format Selection'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.find'),
                    onPressed: active == null ? null : _handleFind,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Find'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.replace'),
                    onPressed: active == null ? null : _handleReplace,
                    icon: const Icon(Icons.find_replace, size: 16),
                    label: const Text('Replace'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.definition'),
                    onPressed: active == null ? null : widget.onGoToDefinition,
                    icon: const Icon(Icons.subdirectory_arrow_right, size: 16),
                    label: const Text('Definition'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.peek'),
                    onPressed: active == null ? null : widget.onPeekDefinition,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Peek'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.references'),
                    onPressed: active == null ? null : widget.onFindReferences,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('References'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.hover'),
                    onPressed: active == null ? null : widget.onHover,
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text('Hover'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.open-symbol'),
                    onPressed: active == null ? null : widget.onOpenSymbol,
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text('Open Symbol'),
                  ),
                  TextButton.icon(
                    key: const Key('editor.workspace-symbol'),
                    onPressed: widget.onWorkspaceSymbol,
                    icon: const Icon(Icons.travel_explore, size: 16),
                    label: const Text('Workspace Symbol'),
                  ),
                  TextButton.icon(
                    onPressed: active == null ? null : widget.onReveal,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Reveal'),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: Text(widget.wordWrap ? 'Wrap On' : 'Wrap Off'),
                    selected: widget.wordWrap,
                    onSelected: (_) => widget.onToggleWordWrap(),
                  ),
                ],
              ),
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
                ? Center(
                    child: Text(
                      'Open a file from Explorer or Search to start editing.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

class _LanguageSidePanel extends StatelessWidget {
  const _LanguageSidePanel({
    required this.hover,
    required this.references,
  });

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
