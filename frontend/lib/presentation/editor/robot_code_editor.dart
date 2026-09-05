import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import '../preferences/editor_font_families.dart';
import 'editor_find_panel.dart';
import 'editor_language_widgets.dart';
import 'editor_navigation_widgets.dart';
import 'editor_run_gutter.dart';
import 'editor_syntax.dart';
import 'robot_code_shortcuts.dart';

class RobotCodeEditor extends StatefulWidget {
  const RobotCodeEditor({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onContentChanged,
    this.onCursorChanged,
    this.onCtrlClick,
    this.onHoverRequest,
    this.onHoverExit,
    this.onSave,
    this.wordWrap = true,
    this.jumpToLine,
    this.jumpToColumn,
    this.onJumpApplied,
    this.completionItems = const [],
    this.diagnostics = const [],
    this.hoverTooltip,
    this.peekDefinition,
    this.onClosePeek,
    this.onCompletionAccepted,
    this.foldingRanges = const [],
    this.runnableTests = const [],
    this.onRunTest,
    this.runTestsEnabled = true,
    this.fontSize = 13,
    this.fontFamily = 'Menlo',
    this.tabWidth = 4,
    this.onBindState,
  });

  final String path;
  final String initialContent;
  final ValueChanged<String> onContentChanged;
  final void Function(int line, int column)? onCursorChanged;
  final VoidCallback? onCtrlClick;

  /// Fired after the pointer rests over a code position (VS Code-style hover).
  final void Function(int line, int column)? onHoverRequest;
  final VoidCallback? onHoverExit;

  /// Wired to ⌘S / Ctrl+S via re_editor save intent override.
  final VoidCallback? onSave;
  final bool wordWrap;
  final int? jumpToLine;
  final int? jumpToColumn;

  /// Called after a jump has been applied so the parent can clear [jumpToLine]
  /// (allows re-clicking the same Outline / Problems row).
  final VoidCallback? onJumpApplied;
  final List<CompletionItemInfo> completionItems;
  final List<DiagnosticInfo> diagnostics;
  final SignatureHelpInfo? hoverTooltip;
  final IndexedSymbolInfo? peekDefinition;
  final VoidCallback? onClosePeek;

  /// Fired when the user accepts an autocomplete item (usage ranking).
  final ValueChanged<CompletionItemInfo>? onCompletionAccepted;
  final List<FoldingRangeInfo> foldingRanges;

  /// Test Cases / Tasks in the open `.robot` file — play controls in the gutter.
  final List<EditorRunnableTest> runnableTests;
  final ValueChanged<EditorRunnableTest>? onRunTest;
  final bool runTestsEnabled;
  final double fontSize;
  final String fontFamily;
  final int tabWidth;

  /// Lets [EditorPage] call find/format without a [GlobalKey] (avoids duplicate-key crashes).
  final ValueChanged<RobotCodeEditorState?>? onBindState;

  @override
  State<RobotCodeEditor> createState() => RobotCodeEditorState();
}

/// The suggestion popup currently in the overlay. [token] discards a stale
/// dismissal that arrives after a newer popup has already opened.
class _AutocompletePopup {
  const _AutocompletePopup(this.token, this.notifier, this.onSelected);

  final int token;
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
}

/// Caret or pointer, in this widget's coordinates, plus the visual row the
/// card must not cover. [lineTop] comes from the editor's laid-out glyphs so
/// word wrap and folded chunks do not shift the card off the caret.
class _RowAnchor {
  const _RowAnchor({required this.offset, this.lineTop, this.lineHeight});

  final Offset offset;
  final double? lineTop;
  final double? lineHeight;
}

class RobotCodeEditorState extends State<RobotCodeEditor> {
  static const _fontHeight = 1.45;
  static const _chunkWidth = 14.0;
  static const _hoverDelay = Duration(milliseconds: 400);
  static const _hoverDismissDelay = Duration(milliseconds: 280);

  /// After a click to place the caret, ignore hover until the pointer moves —
  /// otherwise resting on the same glyph re-opens the card ~400ms later.
  static const _hoverResumeMove = 4.0;

  late CodeLineEditingController _controller;
  late CodeFindController _findController;
  late CodeScrollController _scrollController;
  late final RobotAutocompletePromptsBuilder _promptsBuilder;
  late CodeChunkAnalyzer _chunkAnalyzer;
  List<DiagnosticInfo> _diagnostics = [];
  bool _listening = false;

  /// Last text sent to [RobotCodeEditor.onContentChanged] — suppresses the
  /// spurious mount notification from re_editor's controller delegate=.
  String _lastEmittedContent = '';
  Timer? _hoverTimer;
  Timer? _hoverDismissTimer;
  Offset? _hoverLocal;
  int? _hoverLine;
  int? _hoverColumn;
  Offset? _suppressHoverOrigin;
  double _charWidth = 7.8;
  bool _pointerOverTooltip = false;
  final GlobalKey _hoverTooltipKey = GlobalKey();
  Size _hoverTooltipSize = const Size(360, 88);
  _AutocompletePopup? _popup;
  int _popupToken = 0;
  CodeIndicatorValueNotifier? _indicator;

  CodeLineEditingController get controller => _controller;

  double get _fontSize => widget.fontSize;

  CodeLineSpanBuilder get _spanBuilder =>
      ({
        required BuildContext context,
        required int index,
        required CodeLine codeLine,
        required TextSpan textSpan,
        required TextStyle style,
      }) {
        return buildDiagnosticLineSpan(
          context: context,
          lineNumber: index + 1,
          codeLine: codeLine,
          textSpan: textSpan,
          style: style,
          diagnostics: _diagnostics,
        );
      };

  void _createController(String text) {
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(text),
      spanBuilder: _spanBuilder,
      options: CodeLineOptions(indentSize: widget.tabWidth.clamp(1, 16)),
    );
  }

  CodeFindController get findController => _findController;

  double get _lineHeight => _fontSize * _fontHeight;

  double get _gutterWidth {
    final digits = math.max(3, _controller.lineCount.toString().length);
    final run = widget.runnableTests.isEmpty ? 0.0 : editorRunGutterWidth;
    return digits * _charWidth + 16 + _chunkWidth + run;
  }

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.diagnostics;
    _chunkAnalyzer = RobotDocumentChunkAnalyzer(widget.foldingRanges);
    _createController(widget.initialContent);
    _lastEmittedContent = widget.initialContent;
    _findController = CodeFindController(_controller);
    _scrollController = CodeScrollController();
    _promptsBuilder = RobotAutocompletePromptsBuilder(
      widget.completionItems,
      signature: widget.hoverTooltip,
      filePath: widget.path,
    );
    _controller.addListener(_onChanged);
    _listening = true;
    _measureCharWidth();
    widget.onBindState?.call(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpIfNeeded(widget.jumpToLine, widget.jumpToColumn);
    });
  }

  void _measureCharWidth() {
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          fontSize: _fontSize,
          fontFamily: widget.fontFamily,
          fontFamilyFallback: editorFontFamilyFallback(widget.fontFamily),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;
  }

  @override
  void didUpdateWidget(covariant RobotCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onBindState != widget.onBindState) {
      oldWidget.onBindState?.call(null);
      widget.onBindState?.call(this);
    }
    if (oldWidget.path != widget.path) {
      _applyParentContent(widget.initialContent, preserveSelection: false);
      _dismissHover();
    } else if (shouldApplyParentContent(
      oldParentContent: oldWidget.initialContent,
      newParentContent: widget.initialContent,
      controllerContent: _controller.text,
    )) {
      _applyParentContent(widget.initialContent);
    }
    if (widget.completionItems != oldWidget.completionItems ||
        widget.hoverTooltip != oldWidget.hoverTooltip ||
        widget.path != oldWidget.path) {
      _promptsBuilder.update(
        widget.completionItems,
        signature: widget.hoverTooltip,
        filePath: widget.path,
      );
      // Re-run autocomplete so async completion results pop open without
      // another keystroke (Python Jedi / language refresh is debounced).
      setState(() {});
    }
    if (widget.diagnostics != oldWidget.diagnostics) {
      _diagnostics = widget.diagnostics;
      setState(() {});
    }
    if (!_sameFoldingRanges(oldWidget.foldingRanges, widget.foldingRanges)) {
      _chunkAnalyzer = RobotDocumentChunkAnalyzer(widget.foldingRanges);
      setState(() {});
    }
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontFamily != widget.fontFamily) {
      _measureCharWidth();
      setState(() {});
    }
    if (widget.jumpToLine != null &&
        (widget.jumpToLine != oldWidget.jumpToLine ||
            widget.jumpToColumn != oldWidget.jumpToColumn)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfNeeded(widget.jumpToLine, widget.jumpToColumn);
      });
    }
  }

  bool _sameFoldingRanges(List<FoldingRangeInfo> a, List<FoldingRangeInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].startLine != b[i].startLine || a[i].endLine != b[i].endLine) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    widget.onBindState?.call(null);
    _hoverTimer?.cancel();
    _hoverDismissTimer?.cancel();
    _dismissAutocompleteOverlay();
    if (_listening) {
      _controller.removeListener(_onChanged);
    }
    _findController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// When to push [initialContent] from the shell into the live controller.
  ///
  /// Only when the parent moved forward and the controller still matches the
  /// previous parent snapshot (disk reload). While the user types ahead of a
  /// stale [EditorTabInfo.content], skip — that mismatch caused the caret to
  /// jump to column 1 on fast input.
  @visibleForTesting
  static bool shouldApplyParentContent({
    required String oldParentContent,
    required String newParentContent,
    required String controllerContent,
  }) {
    if (newParentContent == controllerContent) return false;
    if (newParentContent == oldParentContent) return false;
    return controllerContent == oldParentContent;
  }

  void _applyParentContent(String content, {bool preserveSelection = true}) {
    final selection = preserveSelection ? _controller.selection : null;
    _controller.removeListener(_onChanged);
    _controller.text = content;
    if (preserveSelection && selection != null) {
      _controller.selection = selection;
    }
    _lastEmittedContent = content;
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    final text = _controller.text;
    // Mount / delegate= notifies without a real edit — avoid climbing into
    // AppShell.setState during CodeEditor's first build.
    if (text != _lastEmittedContent) {
      _lastEmittedContent = text;
      widget.onContentChanged(text);
    }
    final sel = _controller.selection;
    widget.onCursorChanged?.call(sel.baseIndex + 1, sel.baseOffset + 1);
  }

  /// Accept the highlighted completion, mirroring what Enter does inside
  /// `CodeAutocomplete`. Returns false when no popup is open.
  bool _acceptOpenCompletion() {
    final popup = _popup;
    if (popup == null) return false;
    final value = popup.notifier.value;
    if (value.prompts.isEmpty) return false;
    final result = value.autocomplete;
    _recordCompletionAcceptance(result.word);
    popup.onSelected(result);
    return true;
  }

  void _recordCompletionAcceptance(String insertWord) {
    final callback = widget.onCompletionAccepted;
    if (callback == null) return;
    CompletionItemInfo? match;
    for (final item in widget.completionItems) {
      if (item.insertText == insertWord || item.label == insertWord) {
        match = item;
        break;
      }
    }
    if (match != null) {
      callback(match);
    }
  }

  void _jumpIfNeeded(int? line, [int? column]) {
    if (line == null || line < 1) return;
    final index = line - 1;
    if (index >= _controller.lineCount) return;
    final row = _controller.codeLines[index];
    final maxOffset = row.length;
    final offset = ((column ?? 1) - 1).clamp(0, maxOffset);
    final position = CodeLinePosition(index: index, offset: offset);
    _controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    // Selection alone does not scroll — Outline / Go to Definition need this.
    _scrollController.makeCenterIfInvisible(position);
    widget.onJumpApplied?.call();
  }

  void showFind({bool replace = false}) {
    if (replace) {
      _findController.replaceMode();
    } else {
      _findController.findMode();
    }
  }

  /// Overwrite the visible buffer (Format Document, disk reload).
  ///
  /// Does not use [shouldApplyParentContent] — that guard skips parent updates
  /// when the controller has diverged, which is correct for typing but would
  /// swallow an explicit format.
  void applyExternalContent(String content, {bool preserveSelection = true}) {
    if (_controller.text == content) return;
    _applyParentContent(content, preserveSelection: preserveSelection);
  }

  void undo() => _controller.undo();
  void redo() => _controller.redo();

  /// Duplicate selected lines above or below (VS Code Shift+Opt/Alt+↑/↓).
  void copyLines(VerticalDirection direction) {
    final selection = _controller.selection;
    final start = selection.startIndex;
    final end = selection.endIndex;
    final copies = <CodeLine>[
      for (var i = start; i <= end; i++)
        CodeLine(_controller.codeLines[i].text),
    ];
    final insertAt = direction == VerticalDirection.down ? end + 1 : start;
    final all = <CodeLine>[];
    for (var i = 0; i < _controller.lineCount; i++) {
      if (i == insertAt) {
        all.addAll(copies);
      }
      all.add(CodeLine(_controller.codeLines[i].text));
    }
    if (insertAt >= _controller.lineCount) {
      all.addAll(copies);
    }
    final newStart = insertAt;
    final newEnd = insertAt + copies.length - 1;
    _controller.runRevocableOp(() {
      _controller.value = _controller.value.copyWith(
        codeLines: CodeLines.of(all),
        selection: CodeLineSelection(
          baseIndex: newStart,
          baseOffset: 0,
          extentIndex: newEnd,
          extentOffset: copies.last.length,
        ),
      );
    });
  }

  int? get selectionStartLine {
    final sel = _controller.selection;
    return sel.startIndex + 1;
  }

  int? get selectionEndLine {
    final sel = _controller.selection;
    return sel.endIndex + 1;
  }

  void _onEscape() {
    // Find panel owns Escape while open.
    if (_findController.value != null) {
      _findController.close();
      return;
    }
    _dismissAutocompleteOverlay();
    _dismissHover(immediate: true);
  }

  /// re_editor only enables Esc when find is open or the selection is expanded,
  /// so a normal collapsed-caret suggestion popup never receives Escape.
  /// Flipping caret affinity notifies without moving the caret and hits the
  /// unchanged-codeLines dismiss path in re_editor.
  void _dismissAutocompleteOverlay() {
    final sel = _controller.selection;
    final flipped = sel.baseAffinity == TextAffinity.downstream
        ? TextAffinity.upstream
        : TextAffinity.downstream;
    _controller.selection = sel.copyWith(
      baseAffinity: flipped,
      extentAffinity: flipped,
    );
  }

  void _dismissHover({bool immediate = false}) {
    if (!immediate && _pointerOverTooltip) return;
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoverDismissTimer?.cancel();
    _hoverDismissTimer = null;
    _pointerOverTooltip = false;
    final hadTooltip = widget.hoverTooltip != null || _hoverLocal != null;
    _hoverLocal = null;
    _hoverLine = null;
    _hoverColumn = null;
    _hoverTooltipSize = const Size(360, 88);
    if (hadTooltip) {
      widget.onHoverExit?.call();
      if (mounted) setState(() {});
    }
  }

  /// Python docs only for an identifier under the pointer — blank parts of a
  /// line must not open the card.
  bool _isPythonHoverTarget(int line, int column) {
    final index = line - 1;
    if (index < 0 || index >= _controller.lineCount) return false;
    final text = _controller.codeLines[index].text;
    final i = column - 1;
    if (i < 0 || i >= text.length) return false;
    final code = text.codeUnitAt(i);
    final isAz = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    final isDigit = code >= 48 && code <= 57;
    return isAz || isDigit || code == 95; // letter, digit, or _
  }

  void _scheduleDismissHover() {
    _hoverDismissTimer?.cancel();
    _hoverDismissTimer = Timer(_hoverDismissDelay, () {
      if (!mounted || _pointerOverTooltip) return;
      _dismissHover(immediate: true);
    });
  }

  bool _isPointerOverTooltip(Offset localInEditor) {
    // State.mounted stays true after deactivate(); context.mounted does not.
    // Hover still arrives on the old Listener during a tab/view swap.
    if (!context.mounted) return false;
    final tooltipContext = _hoverTooltipKey.currentContext;
    if (tooltipContext == null || !tooltipContext.mounted) return false;
    final box = tooltipContext.findRenderObject() as RenderBox?;
    final editorBox = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || editorBox == null || !editorBox.hasSize) {
      return false;
    }
    final global = editorBox.localToGlobal(localInEditor);
    final tooltipLocal = box.globalToLocal(global);
    // Slightly inflate so the gap between caret and card is still "sticky".
    final hit = Rect.fromLTWH(
      -8,
      -8,
      box.size.width + 16,
      box.size.height + 16,
    );
    return hit.contains(tooltipLocal);
  }

  /// Laid-out rows currently on screen, in this widget's coordinates.
  ///
  /// The editor publishes these for its own gutter, already offset by the
  /// scroll position. Everything that has to line up with a glyph reads them
  /// instead of multiplying a line index by [_lineHeight]: that arithmetic
  /// assumes one row per line of uniform height, which word wrap (on by
  /// default) and collapsed chunks both break, and the error grows with every
  /// wrapped row above the caret.
  List<CodeLineRenderParagraph> get _rows =>
      _indicator?.value?.paragraphs ?? const [];

  CodeLineRenderParagraph? _rowForLine(int lineIndex) {
    for (final row in _rows) {
      if (row.index == lineIndex) return row;
    }
    return null;
  }

  CodeLineRenderParagraph? _rowAtY(double dy) {
    for (final row in _rows) {
      if (dy >= row.top && dy < row.bottom) return row;
    }
    return null;
  }

  _RowAnchor _caretAnchor() {
    final sel = _controller.selection;
    final row = _rowForLine(sel.extentIndex);
    final caret = row?.getOffset(sel.extent);
    if (row == null || caret == null) {
      final vertical = _scrollController.verticalScroller.hasClients
          ? _scrollController.verticalScroller.offset
          : 0.0;
      final fallbackY = sel.extentIndex * _lineHeight - vertical;
      return _RowAnchor(
        offset: Offset(
          (_gutterWidth + sel.extentOffset * _charWidth + 8).clamp(8.0, 480.0),
          fallbackY,
        ),
      );
    }
    // A wrapped line is one row object several rows tall, so the caret's own
    // dy — not the row's top — is the line the card must not cover.
    final top = row.top + caret.dy;
    final x = _gutterWidth + row.offset.dx + caret.dx + 8;
    return _RowAnchor(
      offset: Offset(x.clamp(8.0, 480.0), top),
      lineTop: top,
      lineHeight: row.preferredLineHeight,
    );
  }

  _RowAnchor _pointerAnchor(Offset local) {
    final row = _rowAtY(local.dy);
    if (row == null) {
      final lineTop = (local.dy / _lineHeight).floor() * _lineHeight;
      return _RowAnchor(offset: Offset(local.dx, lineTop), lineTop: lineTop);
    }
    final rowHeight = row.preferredLineHeight;
    final top =
        row.top + ((local.dy - row.top) / rowHeight).floor() * rowHeight;
    return _RowAnchor(
      offset: Offset(local.dx, top),
      lineTop: top,
      lineHeight: rowHeight,
    );
  }

  (int, int)? _lineColumnAt(Offset local) {
    final row = _rowAtY(local.dy);
    if (row != null) {
      final inRow = Offset(
        local.dx - _gutterWidth - row.offset.dx,
        local.dy - row.top,
      );
      if (inRow.dx < -2) return null;
      final position = row.getPosition(inRow);
      return (row.index + 1, position.offset + 1);
    }

    final vertical = _scrollController.verticalScroller.hasClients
        ? _scrollController.verticalScroller.offset
        : 0.0;
    final horizontal = _scrollController.horizontalScroller.hasClients
        ? _scrollController.horizontalScroller.offset
        : 0.0;
    final dy = local.dy + vertical;
    final dx = local.dx - _gutterWidth + horizontal;
    if (dx < -2) return null;
    final lineIndex = (dy / _lineHeight).floor();
    if (lineIndex < 0 || lineIndex >= _controller.lineCount) return null;
    final column = math.max(1, (dx / _charWidth).floor() + 1);
    return (lineIndex + 1, column);
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (!context.mounted) return;
    final local = event.localPosition;
    _hoverDismissTimer?.cancel();

    // Click-to-place-caret: ignore dwell until the pointer actually moves.
    final suppressOrigin = _suppressHoverOrigin;
    if (suppressOrigin != null) {
      if ((local - suppressOrigin).distance < _hoverResumeMove) {
        return;
      }
      _suppressHoverOrigin = null;
    }

    // Keep the card while the pointer is on (or near) it so the user can
    // scroll long docs — IgnorePointer used to make this impossible.
    if (widget.hoverTooltip != null && _isPointerOverTooltip(local)) {
      _pointerOverTooltip = true;
      return;
    }
    _pointerOverTooltip = false;

    final hit = _lineColumnAt(local);
    if (hit == null) {
      _scheduleDismissHover();
      return;
    }
    final (line, column) = hit;
    if (isPythonPath(widget.path) && !_isPythonHoverTarget(line, column)) {
      _scheduleDismissHover();
      return;
    }
    final movedFar =
        _hoverLocal == null ||
        (local - _hoverLocal!).distance > 6 ||
        line != _hoverLine ||
        column != _hoverColumn;
    _hoverLocal = local;
    _hoverLine = line;
    _hoverColumn = column;
    if (movedFar) {
      // Do not clear the existing tooltip immediately — clearing on every
      // small move made the card vanish before the pointer could reach it.
      _hoverTimer?.cancel();
      _hoverTimer = Timer(_hoverDelay, () {
        if (!mounted || _pointerOverTooltip) return;
        if (_suppressHoverOrigin != null) return;
        widget.onHoverRequest?.call(line, column);
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPython = isPythonPath(widget.path);
    final autocompleteEnabled = isSourcePath(widget.path);
    final codeTheme = codeThemeForPath(widget.path, context.palette);

    final editor = CodeEditor(
      controller: _controller,
      findController: _findController,
      scrollController: _scrollController,
      wordWrap: widget.wordWrap,
      chunkAnalyzer: _chunkAnalyzer,
      commentFormatter: DefaultCodeCommentFormatter(singleLinePrefix: '#'),
      shortcutsActivatorsBuilder: const RobotCodeShortcutsActivatorsBuilder(),
      shortcutOverrideActions: {
        CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
          onInvoke: (_) {
            widget.onSave?.call();
            return null;
          },
        ),
        // Tab accepts the completion like every other editor; it only indents
        // when no popup is open.
        CodeShortcutIndentIntent: CallbackAction<CodeShortcutIndentIntent>(
          onInvoke: (_) {
            if (_acceptOpenCompletion()) return null;
            _controller.applyIndent();
            return null;
          },
        ),
        // Overriding newline takes over the popup's Enter handling too, so
        // accepting has to be re-applied here before the suite indent.
        CodeShortcutNewLineIntent: CallbackAction<CodeShortcutNewLineIntent>(
          onInvoke: (_) {
            if (_acceptOpenCompletion()) return null;
            final selection = _controller.selection;
            final opensSuite =
                isPython &&
                selection.isCollapsed &&
                selection.extentIndex < _controller.lineCount &&
                opensPythonSuite(
                  _controller.codeLines[selection.extentIndex].text,
                  selection.extentOffset,
                );
            _controller.applyNewLine();
            if (opensSuite) _controller.applyIndent();
            return null;
          },
        ),
      },
      style: CodeEditorStyle(
        fontSize: _fontSize,
        fontFamily: widget.fontFamily,
        fontFamilyFallback: editorFontFamilyFallback(widget.fontFamily),
        fontHeight: _fontHeight,
        backgroundColor: context.palette.background,
        textColor: context.palette.textPrimary,
        cursorColor: context.palette.accent,
        selectionColor: context.palette.accentSoft,
        highlightColor: context.palette.accent.withValues(alpha: 0.2),
        codeTheme: codeTheme,
      ),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            // Same notifier the gutter paints from — it carries the real row
            // geometry, which is the only way to anchor a card on a glyph.
            _indicator = notifier;
            return Row(
              children: [
                if (widget.runnableTests.isNotEmpty)
                  RobotTestRunGutter(
                    notifier: notifier,
                    tests: widget.runnableTests,
                    onRun: widget.onRunTest,
                    enabled: widget.runTestsEnabled,
                  ),
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                ),
                DefaultCodeChunkIndicator(
                  width: _chunkWidth,
                  controller: chunkController,
                  notifier: notifier,
                ),
              ],
            );
          },
      findBuilder: (context, controller, readOnly) =>
          EditorFindPanel(controller: controller, readOnly: readOnly),
    );

    final wrappedEditor = autocompleteEnabled
        ? CodeAutocomplete(
            viewBuilder: (context, notifier, onSelected) {
              // The popup lives in an overlay we do not own, so the list view
              // reports its own lifetime — that is how Tab knows one is open.
              final token = ++_popupToken;
              _popup = _AutocompletePopup(token, notifier, onSelected);
              return RobotAutocompleteListView(
                notifier: notifier,
                onSelected: (result) {
                  _recordCompletionAcceptance(result.word);
                  onSelected(result);
                },
                onDismissed: () {
                  if (_popup?.token == token) _popup = null;
                },
              );
            },
            promptsBuilder: _promptsBuilder,
            child: editor,
          )
        : editor;

    final tooltip = widget.hoverTooltip;
    final fromCaret = _hoverLocal == null;
    final anchor = _hoverLocal != null
        ? _pointerAnchor(_hoverLocal!)
        : (tooltip != null ? _caretAnchor() : null);
    // Caret-driven signature help shares the caret line with the completion
    // popup, which always opens below it.
    final tooltipAbove = fromCaret;
    final tooltipMaxHeight = fromCaret
        ? EditorHoverTooltip.compactMaxHeight
        : EditorHoverTooltip.maxHeight;

    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, meta: true):
            const _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, control: true):
            const _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            const _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.f12):
            const _DefinitionIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _DismissSignatureIntent(),
        // Copy line — VS Code Shift+Option/Alt+↑/↓
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          shift: true,
          alt: true,
        ): const CopyLineIntent(
          VerticalDirection.up,
        ),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          shift: true,
          alt: true,
        ): const CopyLineIntent(
          VerticalDirection.down,
        ),
      },
      child: Actions(
        actions: {
          _FindIntent: CallbackAction<_FindIntent>(
            onInvoke: (_) {
              showFind();
              return null;
            },
          ),
          _ReplaceIntent: CallbackAction<_ReplaceIntent>(
            onInvoke: (_) {
              showFind(replace: true);
              return null;
            },
          ),
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              undo();
              return null;
            },
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) {
              redo();
              return null;
            },
          ),
          _DefinitionIntent: CallbackAction<_DefinitionIntent>(
            onInvoke: (_) {
              widget.onCtrlClick?.call();
              return null;
            },
          ),
          _DismissSignatureIntent: CallbackAction<_DismissSignatureIntent>(
            onInvoke: (_) {
              _onEscape();
              return null;
            },
          ),
          CopyLineIntent: CallbackAction<CopyLineIntent>(
            onInvoke: (intent) {
              copyLines(intent.direction);
              return null;
            },
          ),
        },
        child: MouseRegion(
          onExit: (_) {
            _suppressHoverOrigin = null;
            _scheduleDismissHover();
          },
          child: Listener(
            onPointerHover: _onPointerHover,
            onPointerDown: (event) {
              _suppressHoverOrigin = event.localPosition;
              _dismissHover(immediate: true);
              final pressed = HardwareKeyboard.instance.logicalKeysPressed;
              final ctrl =
                  pressed.contains(LogicalKeyboardKey.controlLeft) ||
                  pressed.contains(LogicalKeyboardKey.controlRight) ||
                  pressed.contains(LogicalKeyboardKey.metaLeft) ||
                  pressed.contains(LogicalKeyboardKey.metaRight);
              if (ctrl && event.buttons == kPrimaryMouseButton) {
                widget.onCtrlClick?.call();
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final placement =
                    tooltip != null &&
                        anchor != null &&
                        viewport.width.isFinite &&
                        viewport.height.isFinite
                    ? computeHoverTooltipPlacement(
                        anchor: anchor.offset,
                        viewport: viewport,
                        tooltipSize: _hoverTooltipSize,
                        lineHeight: anchor.lineHeight ?? _lineHeight,
                        gap: AppSpacing.sm,
                        preferAbove: tooltipAbove,
                        lineTop: anchor.lineTop,
                        maxHeight: tooltipMaxHeight,
                      )
                    : null;

                if (tooltip != null && anchor != null && placement != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _refineHoverTooltipPlacement(
                      anchor: anchor.offset,
                      viewport: viewport,
                      current: placement,
                      preferAbove: tooltipAbove,
                      lineTop: anchor.lineTop,
                      lineHeight: anchor.lineHeight ?? _lineHeight,
                      maxHeight: tooltipMaxHeight,
                    );
                  });
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    wrappedEditor,
                    if (tooltip != null && placement != null)
                      Positioned(
                        left: placement.left,
                        top: placement.top,
                        child: MouseRegion(
                          onEnter: (_) {
                            _pointerOverTooltip = true;
                            _hoverDismissTimer?.cancel();
                          },
                          onExit: (_) {
                            _pointerOverTooltip = false;
                            _scheduleDismissHover();
                          },
                          child: EditorHoverTooltip(
                            key: _hoverTooltipKey,
                            signature: tooltip,
                            compact: fromCaret,
                          ),
                        ),
                      ),
                    if (widget.peekDefinition != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: PeekDefinitionPanel(
                          symbol: widget.peekDefinition!,
                          onOpen: widget.onCtrlClick ?? () {},
                          onClose: widget.onClosePeek ?? () {},
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _refineHoverTooltipPlacement({
    required Offset anchor,
    required Size viewport,
    required HoverTooltipPlacement current,
    bool preferAbove = false,
    double? lineTop,
    double? lineHeight,
    double maxHeight = EditorHoverTooltip.maxHeight,
  }) {
    if (!context.mounted || widget.hoverTooltip == null) return;
    final tooltipContext = _hoverTooltipKey.currentContext;
    if (tooltipContext == null || !tooltipContext.mounted) return;
    final box = tooltipContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if ((box.size.width - _hoverTooltipSize.width).abs() > 0.5 ||
        (box.size.height - _hoverTooltipSize.height).abs() > 0.5) {
      _hoverTooltipSize = box.size;
      setState(() {});
      return;
    }
    final refined = computeHoverTooltipPlacement(
      anchor: anchor,
      viewport: viewport,
      tooltipSize: box.size,
      lineHeight: lineHeight ?? _lineHeight,
      gap: AppSpacing.sm,
      preferAbove: preferAbove,
      lineTop: lineTop,
      maxHeight: maxHeight,
    );
    if ((refined.left - current.left).abs() > 0.5 ||
        (refined.top - current.top).abs() > 0.5) {
      setState(() {});
    }
  }
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _ReplaceIntent extends Intent {
  const _ReplaceIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _DefinitionIntent extends Intent {
  const _DefinitionIntent();
}

class _DismissSignatureIntent extends Intent {
  const _DismissSignatureIntent();
}

/// Folding ranges from DocumentSymbolTree (0-based inclusive → CodeChunk).
class RobotDocumentChunkAnalyzer implements CodeChunkAnalyzer {
  RobotDocumentChunkAnalyzer(this.ranges);

  final List<FoldingRangeInfo> ranges;

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final chunks = <CodeChunk>[];
    final maxLine = codeLines.length;
    for (final range in ranges) {
      final start = range.startLine.clamp(0, math.max(0, maxLine - 1)).toInt();
      // CodeChunk.end is exclusive of the last collapsed line's successor.
      final end = (range.endLine + 1).clamp(start + 1, maxLine).toInt();
      if (end - start > 1) {
        chunks.add(CodeChunk(start, end));
      }
    }
    chunks.sort((a, b) => a.index - b.index);
    return chunks;
  }
}
