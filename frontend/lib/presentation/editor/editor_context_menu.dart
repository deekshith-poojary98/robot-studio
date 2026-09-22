import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../widgets/app_menu.dart';

/// Desktop right-click menu for [CodeEditor] (Cut/Copy/Paste + language actions).
///
/// Wired via [CodeEditor.toolbarController]. [showMenu] is fire-and-forget from
/// the sync [show] entry point re_editor calls on secondary tap.
class EditorContextMenuController implements SelectionToolbarController {
  EditorContextMenuController({
    this.onGoToDefinition,
    this.onFindReferences,
    this.onImpactAnalysis,
    this.onPeekDefinition,
    this.onRenameSymbol,
    this.onFormatDocument,
    this.onFind,
    this.onReplace,
  });

  final VoidCallback? onGoToDefinition;
  final VoidCallback? onFindReferences;
  final VoidCallback? onImpactAnalysis;
  final VoidCallback? onPeekDefinition;
  final VoidCallback? onRenameSymbol;
  final VoidCallback? onFormatDocument;
  final VoidCallback? onFind;
  final VoidCallback? onReplace;

  bool _showing = false;

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    if (_showing) return;
    // re_editor invokes this synchronously from the gesture; defer so the
    // caret move from secondary-tap settles before Go to Definition reads it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(_showMenu(context, controller, anchors.primaryAnchor));
    });
  }

  @override
  void hide(BuildContext context) {
    // [showMenu] dismisses itself; nothing to tear down.
  }

  Future<void> _showMenu(
    BuildContext context,
    CodeLineEditingController controller,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) return;

    final hasSelection = !controller.selection.isCollapsed;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    _showing = true;
    String? selected;
    try {
      selected = await showMenu<String>(
        context: context,
        position: position,
        items: [
          AppPopupMenuItem(
            value: 'cut',
            enabled: hasSelection,
            child: const Text('Cut'),
          ),
          AppPopupMenuItem(
            value: 'copy',
            enabled: hasSelection,
            child: const Text('Copy'),
          ),
          const AppPopupMenuItem(value: 'paste', child: Text('Paste')),
          const AppPopupMenuItem(
            value: 'select_all',
            child: Text('Select All'),
          ),
          const AppPopupMenuDivider(),
          AppPopupMenuItem(
            value: 'definition',
            enabled: onGoToDefinition != null,
            child: const Text('Go to Definition'),
          ),
          AppPopupMenuItem(
            value: 'peek',
            enabled: onPeekDefinition != null,
            child: const Text('Peek Definition'),
          ),
          AppPopupMenuItem(
            value: 'references',
            enabled: onFindReferences != null,
            child: const Text('Find References'),
          ),
          AppPopupMenuItem(
            value: 'impact',
            enabled: onImpactAnalysis != null,
            child: const Text('Impact Analysis'),
          ),
          const AppPopupMenuDivider(),
          AppPopupMenuItem(
            value: 'rename',
            enabled: onRenameSymbol != null,
            child: const Text('Rename Symbol…'),
          ),
          AppPopupMenuItem(
            value: 'format',
            enabled: onFormatDocument != null,
            child: const Text('Format Document'),
          ),
          const AppPopupMenuDivider(),
          AppPopupMenuItem(
            value: 'find',
            enabled: onFind != null,
            child: const Text('Find…'),
          ),
          AppPopupMenuItem(
            value: 'replace',
            enabled: onReplace != null,
            child: const Text('Replace…'),
          ),
        ],
      );
    } finally {
      _showing = false;
    }

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'cut':
        controller.cut();
      case 'copy':
        unawaited(controller.copy());
      case 'paste':
        controller.paste();
      case 'select_all':
        controller.selectAll();
      case 'definition':
        onGoToDefinition?.call();
      case 'peek':
        onPeekDefinition?.call();
      case 'references':
        onFindReferences?.call();
      case 'impact':
        onImpactAnalysis?.call();
      case 'rename':
        onRenameSymbol?.call();
      case 'format':
        onFormatDocument?.call();
      case 'find':
        onFind?.call();
      case 'replace':
        onReplace?.call();
    }
  }
}
