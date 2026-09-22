import 'package:flutter/material.dart';

import '../../core/gateway/models/file_info.dart';
import '../../core/gateway/models/impact_info.dart';
import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import 'editor_navigation_widgets.dart';
import 'editor_run_gutter.dart';
import 'editor_start_page.dart';
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
    this.impact,
    this.onOpenImpactHit,
    this.onDismissImpact,
    this.onRunImpactSet,
    this.runImpactEnabled = true,
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
    this.onGoToDefinition,
    this.onPeekDefinition,
    this.onFindReferences,
    this.onImpactAnalysis,
    this.onRenameSymbol,
    this.onFormatDocument,
    required this.onHoverRequest,
    required this.onHoverExit,
    required this.onCtrlClick,
    required this.onClosePeek,
    required this.onCursorChanged,
    this.onViewportChanged,
    this.jumpToLine,
    this.jumpToColumn,
    this.onJumpApplied,
    this.onCompletionAccepted,
    this.foldingRanges = const [],
    this.runnableTests = const [],
    this.onRunTest,
    this.runTestsEnabled = true,
    this.fontSize = 13,
    this.fontFamily = 'Menlo',
    this.tabWidth = 4,
    this.startPageTitle,
    this.startPagePath,
    this.recentFiles = const [],
    this.onOpenFilePalette,
    this.onOpenRecentFile,
    this.onSearchProject,
    this.onShowExplorer,
    this.explorerVisible = false,
    this.onManageEnvironments,
    this.onRunProject,
  });

  final List<EditorTabInfo> tabs;
  final String? activePath;
  final bool wordWrap;
  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final ImpactReportInfo? impact;
  final ValueChanged<ImpactHitInfo>? onOpenImpactHit;
  final VoidCallback? onDismissImpact;
  final VoidCallback? onRunImpactSet;
  final bool runImpactEnabled;
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
  final VoidCallback? onGoToDefinition;
  final VoidCallback? onPeekDefinition;
  final VoidCallback? onFindReferences;
  final VoidCallback? onImpactAnalysis;
  final VoidCallback? onRenameSymbol;
  final VoidCallback? onFormatDocument;
  final void Function(int line, int column) onHoverRequest;
  final VoidCallback onHoverExit;
  final void Function(int line, int column) onCtrlClick;
  final VoidCallback onClosePeek;
  final void Function(int line, int column) onCursorChanged;
  final void Function(String path, double offsetX, double offsetY)?
  onViewportChanged;
  final int? jumpToLine;
  final int? jumpToColumn;
  final VoidCallback? onJumpApplied;
  final ValueChanged<CompletionItemInfo>? onCompletionAccepted;
  final List<FoldingRangeInfo> foldingRanges;
  final List<EditorRunnableTest> runnableTests;
  final ValueChanged<EditorRunnableTest>? onRunTest;
  final bool runTestsEnabled;
  final double fontSize;
  final String fontFamily;
  final int tabWidth;

  /// Shown when no editor tab is active (replaces the blank empty state).
  final String? startPageTitle;
  final String? startPagePath;
  final List<String> recentFiles;
  final VoidCallback? onOpenFilePalette;
  final ValueChanged<String>? onOpenRecentFile;
  final VoidCallback? onSearchProject;
  final VoidCallback? onShowExplorer;
  final bool explorerVisible;
  final VoidCallback? onManageEnvironments;
  final VoidCallback? onRunProject;

  @override
  State<EditorPage> createState() => EditorPageState();
}

class EditorPageState extends State<EditorPage> {
  RobotCodeEditorState? _editor;

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
    _editor?.showFind(replace: replace);
  }

  /// Live buffer, including keystrokes that have not yet rebuilt the shell.
  String? get currentText => _editor?.controller.text;

  /// Push formatted / reloaded text into the visible editor.
  void applyExternalContent(String content) {
    _editor?.applyExternalContent(content);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Container(
      key: const Key('editor.page'),
      color: context.palette.background,
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
              color: context.palette.accentSoft,
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
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: active == null
                ? EditorStartPage(
                    title: widget.startPageTitle ?? 'Robot Studio',
                    path: widget.startPagePath ?? '',
                    recentFiles: widget.recentFiles,
                    onOpenFile: widget.onOpenFilePalette,
                    onOpenRecentFile: widget.onOpenRecentFile,
                    onSearchProject: widget.onSearchProject,
                    onShowExplorer: widget.onShowExplorer,
                    explorerVisible: widget.explorerVisible,
                    onManageEnvironments: widget.onManageEnvironments,
                    onRunProject: widget.onRunProject,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: RobotCodeEditor(
                          key: ValueKey<String>(active.path),
                          path: active.path,
                          initialContent: active.content,
                          wordWrap: widget.wordWrap,
                          jumpToLine: widget.jumpToLine,
                          jumpToColumn: widget.jumpToColumn,
                          onJumpApplied: widget.onJumpApplied,
                          completionItems: widget.completionItems,
                          diagnostics: widget.diagnostics,
                          hoverTooltip: widget.hoverTooltip,
                          peekDefinition: widget.peekDefinition,
                          onClosePeek: widget.onClosePeek,
                          onCtrlClick: widget.onCtrlClick,
                          onHoverRequest: widget.onHoverRequest,
                          onHoverExit: widget.onHoverExit,
                          onSave: widget.onSave,
                          onGoToDefinition: widget.onGoToDefinition,
                          onPeekDefinition: widget.onPeekDefinition,
                          onFindReferences: widget.onFindReferences,
                          onImpactAnalysis: widget.onImpactAnalysis,
                          onRenameSymbol: widget.onRenameSymbol,
                          onFormatDocument: widget.onFormatDocument,
                          onContentChanged: (content) =>
                              widget.onContentChanged(active.path, content),
                          onCursorChanged: widget.onCursorChanged,
                          onViewportChanged: widget.onViewportChanged == null
                              ? null
                              : (offsetX, offsetY) => widget.onViewportChanged!(
                                  active.path,
                                  offsetX,
                                  offsetY,
                                ),
                          initialScrollOffsetX: active.scrollOffsetX,
                          initialScrollOffsetY: active.scrollOffsetY,
                          initialCaretLine: active.cursorLine,
                          initialCaretColumn: active.cursorColumn,
                          onCompletionAccepted: widget.onCompletionAccepted,
                          foldingRanges: widget.foldingRanges,
                          runnableTests: widget.runnableTests,
                          onRunTest: widget.onRunTest,
                          runTestsEnabled: widget.runTestsEnabled,
                          fontSize: widget.fontSize,
                          fontFamily: widget.fontFamily,
                          tabWidth: widget.tabWidth,
                          onBindState: (state) => _editor = state,
                        ),
                      ),
                      if (widget.hover != null ||
                          widget.references.isNotEmpty ||
                          widget.impact != null)
                        SizedBox(
                          width: 280,
                          child: _LanguageSidePanel(
                            hover: widget.hover,
                            references: widget.references,
                            impact: widget.impact,
                            onOpenImpactHit: widget.onOpenImpactHit,
                            onDismissImpact: widget.onDismissImpact,
                            onRunImpactSet: widget.onRunImpactSet,
                            runImpactEnabled: widget.runImpactEnabled,
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
    this.impact,
    this.onOpenImpactHit,
    this.onDismissImpact,
    this.onRunImpactSet,
    this.runImpactEnabled = true,
  });

  final HoverInfo? hover;
  final List<SymbolReferenceInfo> references;
  final ImpactReportInfo? impact;
  final ValueChanged<ImpactHitInfo>? onOpenImpactHit;
  final VoidCallback? onDismissImpact;
  final VoidCallback? onRunImpactSet;
  final bool runImpactEnabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.borderSubtle)),
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
          if (impact != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Impact',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onDismissImpact != null)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onDismissImpact,
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              impact!.symbol == null
                  ? 'No matching symbol in the analysis graph'
                  : '${impact!.symbol!.kind}: ${impact!.symbol!.name}',
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (impact!.emptyGraph) ...[
              const SizedBox(height: 8),
              Text(
                'Analysis graph is empty. Rebuild the index after opening a Robot project.',
                style: TextStyle(color: palette.warning, fontSize: 12),
              ),
            ] else if (impact!.allHits.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'No affected tests.',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ] else ...[
              if (onRunImpactSet != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: runImpactEnabled && impact!.items.isNotEmpty
                        ? onRunImpactSet
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(
                      impact!.items.isEmpty
                          ? 'Run Impact Set'
                          : 'Run Impact Set (${impact!.items.length})',
                    ),
                  ),
                ),
                if (impact!.items.isEmpty && impact!.uncertain.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Only uncertain hits — review them before running.',
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ],
              if (impact!.items.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Affected (${impact!.items.length})',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...impact!.items.map(
                  (hit) => _ImpactHitTile(
                    hit: hit,
                    uncertain: false,
                    onTap: onOpenImpactHit == null
                        ? null
                        : () => onOpenImpactHit!(hit),
                  ),
                ),
              ],
              if (impact!.uncertain.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Uncertain (${impact!.uncertain.length})',
                  style: TextStyle(
                    color: palette.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Low-confidence bindings — review before relying on these.',
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                ...impact!.uncertain.map(
                  (hit) => _ImpactHitTile(
                    hit: hit,
                    uncertain: true,
                    onTap: onOpenImpactHit == null
                        ? null
                        : () => onOpenImpactHit!(hit),
                  ),
                ),
              ],
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

class _ImpactHitTile extends StatefulWidget {
  const _ImpactHitTile({
    required this.hit,
    required this.uncertain,
    this.onTap,
  });

  final ImpactHitInfo hit;
  final bool uncertain;
  final VoidCallback? onTap;

  @override
  State<_ImpactHitTile> createState() => _ImpactHitTileState();
}

class _ImpactHitTileState extends State<_ImpactHitTile> {
  bool _hovered = false;

  String get _relationLabel {
    switch (widget.hit.relation) {
      case 'direct_call':
        return 'Direct';
      case 'transitive_call':
        return 'Transitive';
      case 'resource_import':
        return 'Import';
      case 'variable_use':
        return 'Variable';
      case 'self':
        return 'Self';
      default:
        return widget.hit.relation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hit = widget.hit;
    final pathLabel = hit.test.filePath.replaceAll('\\', '/').split('/').last;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: _hovered ? palette.surfaceHover : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.test.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hovered ? palette.accent : palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$pathLabel:${hit.test.line} · $_relationLabel · ${hit.confidence}',
                  style: TextStyle(
                    color: widget.uncertain
                        ? palette.warning
                        : palette.textMuted,
                    fontSize: 11,
                  ),
                ),
                if (hit.why.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hit.why,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
