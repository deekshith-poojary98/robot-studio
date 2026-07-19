import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/theme/app_theme.dart';
import 'editor_find_panel.dart';
import 'robot_language.dart';

class RobotCodeEditor extends StatefulWidget {
  const RobotCodeEditor({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onContentChanged,
    this.onCursorChanged,
    this.wordWrap = true,
    this.jumpToLine,
  });

  final String path;
  final String initialContent;
  final ValueChanged<String> onContentChanged;
  final void Function(int line, int column)? onCursorChanged;
  final bool wordWrap;
  final int? jumpToLine;

  @override
  State<RobotCodeEditor> createState() => RobotCodeEditorState();
}

class RobotCodeEditorState extends State<RobotCodeEditor> {
  late final CodeLineEditingController _controller;
  late final CodeFindController _findController;
  bool _listening = false;

  CodeLineEditingController get controller => _controller;
  CodeFindController get findController => _findController;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.initialContent);
    _findController = CodeFindController(_controller);
    _controller.addListener(_onChanged);
    _listening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpIfNeeded(widget.jumpToLine);
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
      // External reload
      final selection = _controller.selection;
      _controller.removeListener(_onChanged);
      _controller.text = widget.initialContent;
      _controller.selection = selection;
      _controller.addListener(_onChanged);
    }
    if (widget.jumpToLine != null &&
        widget.jumpToLine != oldWidget.jumpToLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfNeeded(widget.jumpToLine);
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
    widget.onContentChanged(_controller.text);
    final sel = _controller.selection;
    widget.onCursorChanged?.call(
      sel.baseIndex + 1,
      sel.baseOffset + 1,
    );
  }

  void _jumpIfNeeded(int? line) {
    if (line == null || line < 1) return;
    final index = line - 1;
    if (index >= _controller.lineCount) return;
    _controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: 0,
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

  @override
  Widget build(BuildContext context) {
    final isRobot = widget.path.endsWith('.robot') ||
        widget.path.endsWith('.resource');

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
        },
        child: CodeEditor(
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
          indicatorBuilder:
              (context, editingController, chunkController, notifier) {
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
