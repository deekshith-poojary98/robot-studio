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
import 'robot_language.dart';

class RobotCodeEditor extends StatefulWidget {
  const RobotCodeEditor({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onContentChanged,
    this.onCursorChanged,
    this.onCtrlClick,
    this.wordWrap = true,
    this.jumpToLine,
    this.jumpToColumn,
    this.completionItems = const [],
    this.diagnostics = const [],
    this.signatureHelp,
    this.peekDefinition,
    this.onClosePeek,
  });

  final String path;
  final String initialContent;
  final ValueChanged<String> onContentChanged;
  final void Function(int line, int column)? onCursorChanged;
  final VoidCallback? onCtrlClick;
  final bool wordWrap;
  final int? jumpToLine;
  final int? jumpToColumn;
  final List<CompletionItemInfo> completionItems;
  final List<DiagnosticInfo> diagnostics;
  final SignatureHelpInfo? signatureHelp;
  final IndexedSymbolInfo? peekDefinition;
  final VoidCallback? onClosePeek;

  @override
  State<RobotCodeEditor> createState() => RobotCodeEditorState();
}

class RobotCodeEditorState extends State<RobotCodeEditor> {
  late CodeLineEditingController _controller;
  late CodeFindController _findController;
  late final RobotAutocompletePromptsBuilder _promptsBuilder;
  List<DiagnosticInfo> _diagnostics = [];
  bool _listening = false;

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

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.diagnostics;
    _createController(widget.initialContent);
    _findController = CodeFindController(_controller);
    _promptsBuilder = RobotAutocompletePromptsBuilder(widget.completionItems);
    _controller.addListener(_onChanged);
    _listening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpIfNeeded(widget.jumpToLine, widget.jumpToColumn);
    });
  }

  @override
  void didUpdateWidget(covariant RobotCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller.removeListener(_onChanged);
      _controller.text = widget.initialContent;
      _controller.addListener(_onChanged);
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
    if (widget.jumpToLine != null &&
        (widget.jumpToLine != oldWidget.jumpToLine ||
            widget.jumpToColumn != oldWidget.jumpToColumn)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfNeeded(widget.jumpToLine, widget.jumpToColumn);
      });
    }
  }

  @override
  void dispose() {
    if (_listening) {
      _controller.removeListener(_onChanged);
    }
    _findController.dispose();
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

  int? get selectionStartLine {
    final sel = _controller.selection;
    return sel.startIndex + 1;
  }

  int? get selectionEndLine {
    final sel = _controller.selection;
    return sel.endIndex + 1;
  }

  @override
  Widget build(BuildContext context) {
    final isRobot =
        widget.path.endsWith('.robot') || widget.path.endsWith('.resource');

    final editor = CodeEditor(
      controller: _controller,
      findController: _findController,
      wordWrap: widget.wordWrap,
      style: CodeEditorStyle(
        fontSize: 13,
        fontFamily: 'Menlo',
        fontHeight: 1.45,
        backgroundColor: AppColors.background,
        textColor: AppColors.textPrimary,
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentSoft,
        highlightColor: const Color(0x334A8F90),
        codeTheme: isRobot
            ? CodeHighlightTheme(
                languages: {
                  'robot': CodeHighlightThemeMode(mode: langRobot),
                },
                theme: robotStudioHighlightTheme,
              )
            : null,
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
            ),
            DefaultCodeChunkIndicator(
              width: 14,
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
                onSelected: onSelected,
              );
            },
            promptsBuilder: _promptsBuilder,
            child: editor,
          )
        : editor;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): _FindIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, meta: true): _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, control: true):
            _ReplaceIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true): _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.f12): _DefinitionIntent(),
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
        },
        child: Listener(
          onPointerDown: (event) {
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
            children: [
              wrappedEditor,
              if (widget.signatureHelp != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: SignatureHelpOverlay(signature: widget.signatureHelp!),
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
