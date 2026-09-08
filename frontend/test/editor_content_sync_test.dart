import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/editor/robot_code_editor.dart';

void main() {
  group('shouldApplyParentContent', () {
    test('skips when user typed ahead of stale parent buffer', () {
      expect(
        RobotCodeEditorState.shouldApplyParentContent(
          oldParentContent: 'Hello',
          newParentContent: 'Hello',
          controllerContent: 'Hellox',
        ),
        isFalse,
      );
    });

    test('skips when parent caught up and matches controller', () {
      expect(
        RobotCodeEditorState.shouldApplyParentContent(
          oldParentContent: 'Hello',
          newParentContent: 'Hellox',
          controllerContent: 'Hellox',
        ),
        isFalse,
      );
    });

    test('applies external reload when controller matches old parent', () {
      expect(
        RobotCodeEditorState.shouldApplyParentContent(
          oldParentContent: 'On disk',
          newParentContent: 'Fresh from disk',
          controllerContent: 'On disk',
        ),
        isTrue,
      );
    });

    test('skips when user diverged before external reload', () {
      expect(
        RobotCodeEditorState.shouldApplyParentContent(
          oldParentContent: 'On disk',
          newParentContent: 'Fresh from disk',
          controllerContent: 'On disk edited',
        ),
        isFalse,
      );
    });

    test('format-style parent update is skipped if the user already typed', () {
      // Format Document must not rely on this guard — it uses
      // applyExternalContent so the visible buffer still updates.
      expect(
        RobotCodeEditorState.shouldApplyParentContent(
          oldParentContent: 'messy   ',
          newParentContent: 'messy',
          controllerContent: 'messy   x',
        ),
        isFalse,
      );
    });
  });

  group('editor focus caret refresh', () {
    testWidgets('refreshes selection notification when focused on Windows', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(_editorApp());
        await tester.pump();

        final state = tester.state<RobotCodeEditorState>(
          find.byType(RobotCodeEditor),
        );
        final focus = tester.widget<Focus>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Focus &&
                widget.focusNode?.debugLabel == 'RobotCodeEditor',
          ),
        );
        focus.focusNode!.unfocus();
        await tester.pump();
        final before = state.controller.selection.baseAffinity;

        focus.focusNode!.requestFocus();
        await tester.pump();

        expect(state.controller.selection.baseAffinity, isNot(before));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not alter selection affinity when focused on macOS', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(_editorApp());
        await tester.pump();

        final state = tester.state<RobotCodeEditorState>(
          find.byType(RobotCodeEditor),
        );
        final focus = tester.widget<Focus>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Focus &&
                widget.focusNode?.debugLabel == 'RobotCodeEditor',
          ),
        );
        focus.focusNode!.unfocus();
        await tester.pump();
        final before = state.controller.selection.baseAffinity;

        focus.focusNode!.requestFocus();
        await tester.pump();

        expect(state.controller.selection.baseAffinity, before);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

Widget _editorApp() {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: RobotCodeEditor(
          path: 'example.robot',
          initialContent: '*** Test Cases ***\nExample\n    Log    Hello\n',
          onContentChanged: (_) {},
        ),
      ),
    ),
  );
}
