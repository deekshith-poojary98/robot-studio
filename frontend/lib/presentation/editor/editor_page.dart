import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';
import 'editor_navigation_widgets.dart';
import 'editor_tabs_bar.dart';
import 'robot_code_editor.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.tabs,
    required this.activePath,
    required this.wordWrap,
    required this.hover,
    required this.references,
    required this.statusMessage,
    this.onDismissStatusMessage,
    required this.breadcrumb,
    this.onBreadcrumbTap,
    required this.completionItems,
    required this.diagnostics,
    required this.hoverTooltip,
    required this.peekDefinition,
    required this.onSelectTab,
    required this.onCloseTab,
    this.onTabContextAction,
    required this.onContentChanged,
    required this.onSave,
    required this.onHoverRequest,
    required this.onHoverExit,
    required this.onCtrlClick,
    required this.onClosePeek,
    required this.onCursorChanged,
    this.jumpToLine,
    this.jumpToColumn,
    this.onCompletionAccepted,
    this.foldingRanges = const [],
  });

  final List<EditorTabInfo> tabs;
  final String? activePath;
  final bool wordWrap;
  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final String? statusMessage;

  /// Dismisses the notice before its auto-expiry.
  final VoidCallback? onDismissStatusMessage;
  final EditorBreadcrumbInfo breadcrumb;
  final ValueChanged<BreadcrumbSegment>? onBreadcrumbTap;
  final List<CompletionItemInfo> completionItems;
  final List<DiagnosticInfo> diagnostics;
  final SignatureHelpInfo? hoverTooltip;
  final IndexedSymbolInfo? peekDefinition;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final void Function(String path, EditorTabContextAction action)?
      onTabContextAction;
  final void Function(String path, String content) onContentChanged;
  final VoidCallback onSave;
  final void Function(int line, int column) onHoverRequest;
  final VoidCallback onHoverExit;
  final VoidCallback onCtrlClick;
  final VoidCallback onClosePeek;
  final void Function(int line, int column) onCursorChanged;
  final int? jumpToLine;
  final int? jumpToColumn;
  final ValueChanged<CompletionItemInfo>? onCompletionAccepted;
  final List<FoldingRangeInfo> foldingRanges;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  final _editorKey = GlobalKey<RobotCodeEditorState>();

  EditorTabInfo? get _active {
    final path = widget.activePath;
    if (path == null) return null;
    for (final tab in widget.tabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  /// Open find / replace — used by the window menu bar and command palette.
  void showFind({bool replace = false}) {
    _editorKey.currentState?.showFind(replace: replace);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Container(
      key: const Key('editor.page'),
      color: AppColors.background,
      child: Column(
        children: [
          EditorTabsBar(
            tabs: widget.tabs,
            activePath: widget.activePath,
            onSelect: widget.onSelectTab,
            onClose: widget.onCloseTab,
            onContextAction: widget.onTabContextAction,
          ),
          EditorBreadcrumbBar(
            breadcrumb: widget.breadcrumb,
            onSegmentTap: widget.onBreadcrumbTap,
          ),
          if (widget.statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                left: 12,
                right: 6,
                top: 4,
                bottom: 4,
              ),
              color: AppColors.accentSoft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.statusMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (widget.onDismissStatusMessage != null)
                    InkWell(
                      onTap: widget.onDismissStatusMessage,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: active == null
                ? const EmptyState(
                    icon: Icons.description_outlined,
                    title: 'No file open',
                    message:
                        'Pick a .robot file in the Explorer, or press ⌘P / '
                        'Ctrl+P to jump to one.',
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
                          hoverTooltip: widget.hoverTooltip,
                          peekDefinition: widget.peekDefinition,
                          onClosePeek: widget.onClosePeek,
                          onCtrlClick: widget.onCtrlClick,
                          onHoverRequest: widget.onHoverRequest,
                          onHoverExit: widget.onHoverExit,
                          onSave: widget.onSave,
                          onContentChanged: (content) =>
                              widget.onContentChanged(active.path, content),
                          onCursorChanged: widget.onCursorChanged,
                          onCompletionAccepted: widget.onCompletionAccepted,
                          foldingRanges: widget.foldingRanges,
                        ),
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
