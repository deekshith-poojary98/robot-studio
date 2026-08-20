import 'package:flutter_test/flutter_test.dart';
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
}
