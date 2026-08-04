import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';
import 'editor_find_panel.dart';
import 'editor_language_widgets.dart';
import 'editor_navigation_widgets.dart';
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
    this.completionItems = const [],
    this.diagnostics = const [],
    this.hoverTooltip,
    this.peekDefinition,
    this.onClosePeek,
    this.onCompletionAccepted,
    this.foldingRanges = const [],
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
  final List<CompletionItemInfo> completionItems;
  final List<DiagnosticInfo> diagnostics;
  final SignatureHelpInfo? hoverTooltip;
  final IndexedSymbolInfo? peekDefinition;
  final VoidCallback? onClosePeek;
  /// Fired when the user accepts an autocomplete item (usage ranking).
  final ValueChanged<CompletionItemInfo>? onCompletionAccepted;
  final List<FoldingRangeInfo> foldingRanges;

  @override
  State<RobotCodeEditor> createState() => RobotCodeEditorState();
}

class RobotCodeEditorState extends State<RobotCodeEditor> {
  static const _fontSize = 13.0;
  static const _fontHeight = 1.45;
  static const _chunkWidth = 14.0;
  static const _hoverDelay = Duration(milliseconds: 400);

  late CodeLineEditingController _controller;
  late CodeFindController _findController;
  late CodeScrollController _scrollController;
  late final RobotAutocompletePromptsBuilder _promptsBuilder;
  late CodeChunkAnalyzer _chunkAnalyzer;
  List<DiagnosticInfo> _diagnostics = [];
  bool _listening = false;
  Timer? _hoverTimer;
  Offset? _hoverLocal;
  int? _hoverLine;
  int? _hoverColumn;
  double _charWidth = 7.8;

  CodeLineEditingController get controller => _controller;

  CodeLineSpanBuilder get _spanBuilder => ({
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
    );
  }

  CodeFindController get findController => _findController;

  double get _lineHeight => _fontSize * _fontHeight;

  double get _gutterWidth {
    final digits = math.max(3, _controller.lineCount.toString().length);
    return digits * _charWidth + 16 + _chunkWidth;
  }

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.diagnostics;
    _chunkAnalyzer = RobotDocumentChunkAnalyzer(widget.foldingRanges);
    _createController(widget.initialContent);
    _findController = CodeFindController(_controller);
    _scrollController = CodeScrollController();
    _promptsBuilder = RobotAutocompletePromptsBuilder(widget.completionItems);
    _controller.addListener(_onChanged);
    _listening = true;
    _measureCharWidth();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpIfNeeded(widget.jumpToLine, widget.jumpToColumn);
    });
  }

  void _measureCharWidth() {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(fontSize: _fontSize, fontFamily: 'Menlo'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;
  }

  @override
  void didUpdateWidget(covariant RobotCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller.removeListener(_onChanged);
      _controller.text = widget.initialContent;
      _controller.addListener(_onChanged);
      _dismissHover();
    } else if (oldWidget.initialContent != widget.initialContent &&
        widget.initialContent != _controller.text) {
      final selection = _controller.selection;
      _controller.removeListener(_onChanged);
      _controller.text = widget.initialContent;
      _controller.selection = selection;
      _controller.addListener(_onChanged);
    }
    if (widget.completionItems != oldWidget.completionItems) {
      _promptsBuilder.update(widget.completionItems);
    }
    if (widget.diagnostics != oldWidget.diagnostics) {
      _diagnostics = widget.diagnostics;
      setState(() {});
    }
    if (!_sameFoldingRanges(oldWidget.foldingRanges, widget.foldingRanges)) {
      _chunkAnalyzer = RobotDocumentChunkAnalyzer(widget.foldingRanges);
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
    _hoverTimer?.cancel();
    if (_listening) {
      _controller.removeListener(_onChanged);
    }
    _findController.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onContentChanged(_controller.text);
      final sel = _controller.selection;
      widget.onCursorChanged?.call(
        sel.baseIndex + 1,
        sel.baseOffset + 1,
      );
    });
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
    _controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
  }

  void showFind({bool replace = false}) {
    if (replace) {
      _findController.replaceMode();
    } else {
      _findController.findMode();
    }
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
    final insertAt =
        direction == VerticalDirection.down ? end + 1 : start;
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

  void _dismissHover() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    final hadTooltip = widget.hoverTooltip != null || _hoverLocal != null;
    _hoverLocal = null;
    _hoverLine = null;
    _hoverColumn = null;
    if (hadTooltip) {
      widget.onHoverExit?.call();
      if (mounted) setState(() {});
    }
  }

  Offset _caretTooltipOffset() {
    final sel = _controller.selection;
    final vertical = _scrollController.verticalScroller.hasClients
        ? _scrollController.verticalScroller.offset
        : 0.0;
    final y = sel.baseIndex * _lineHeight - vertical + _lineHeight + 4;
    final x = _gutterWidth + sel.baseOffset * _charWidth + 8;
    return Offset(x.clamp(8.0, 480.0), y.clamp(8.0, 2000.0));
  }

  (int, int)? _lineColumnAt(Offset local) {
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
    final local = event.localPosition;
    final hit = _lineColumnAt(local);
    if (hit == null) {
      _dismissHover();
      return;
    }
    final (line, column) = hit;
    final movedFar = _hoverLocal == null ||
        (local - _hoverLocal!).distance > 6 ||
        line != _hoverLine ||
        column != _hoverColumn;
    _hoverLocal = local;
    _hoverLine = line;
    _hoverColumn = column;
    if (movedFar) {
      if (widget.hoverTooltip != null) {
        widget.onHoverExit?.call();
      }
      _hoverTimer?.cancel();
      _hoverTimer = Timer(_hoverDelay, () {
        if (!mounted) return;
        widget.onHoverRequest?.call(line, column);
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRobot =
        widget.path.endsWith('.robot') || widget.path.endsWith('.resource');
    final codeTheme = codeThemeForPath(widget.path);

    final editor = CodeEditor(
      controller: _controller,
      findController: _findController,
      scrollController: _scrollController,
      wordWrap: widget.wordWrap,
      chunkAnalyzer: _chunkAnalyzer,
      commentFormatter: DefaultCodeCommentFormatter(
        singleLinePrefix: '#',
      ),
      shortcutsActivatorsBuilder:
          const RobotCodeShortcutsActivatorsBuilder(),
      shortcutOverrideActions: {
        CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
          onInvoke: (_) {
            widget.onSave?.call();
            return null;
          },
        ),
      },
      style: CodeEditorStyle(
        fontSize: _fontSize,
        fontFamily: 'Menlo',
        fontHeight: _fontHeight,
        backgroundColor: AppColors.background,
        textColor: AppColors.textPrimary,
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentSoft,
        highlightColor: const Color(0x334A8F90),
        codeTheme: codeTheme,
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
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
      findBuilder: (context, controller, readOnly) => EditorFindPanel(
        controller: controller,
        readOnly: readOnly,
      ),
    );

    final wrappedEditor = isRobot
        ? CodeAutocomplete(
            viewBuilder: (context, notifier, onSelected) {
              return RobotAutocompleteListView(
                notifier: notifier,
                onSelected: (result) {
                  _recordCompletionAcceptance(result.word);
                  onSelected(result);
                },
              );
            },
            promptsBuilder: _promptsBuilder,
            child: editor,
          )
        : editor;

    final tooltip = widget.hoverTooltip;
    final tooltipPos = _hoverLocal ?? (tooltip != null ? _caretTooltipOffset() : null);

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
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true, alt: true):
            const CopyLineIntent(VerticalDirection.up),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          shift: true,
          alt: true,
        ): const CopyLineIntent(VerticalDirection.down),
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
              _dismissHover();
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
          onExit: (_) => _dismissHover(),
          child: Listener(
            onPointerHover: _onPointerHover,
            onPointerDown: (event) {
              _dismissHover();
              final pressed = HardwareKeyboard.instance.logicalKeysPressed;
              final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
                  pressed.contains(LogicalKeyboardKey.controlRight) ||
                  pressed.contains(LogicalKeyboardKey.metaLeft) ||
                  pressed.contains(LogicalKeyboardKey.metaRight);
              if (ctrl && event.buttons == kPrimaryMouseButton) {
                widget.onCtrlClick?.call();
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                wrappedEditor,
                if (tooltip != null && tooltipPos != null)
                  Positioned(
                    left: math.max(8, tooltipPos.dx + 12),
                    top: math.max(8, tooltipPos.dy + _lineHeight + 4),
                    child: IgnorePointer(
                      child: EditorHoverTooltip(signature: tooltip),
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
            ),
          ),
        ),
      ),
    );
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
