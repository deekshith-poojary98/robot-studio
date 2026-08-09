import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/editor/robot_code_shortcuts.dart';
import 'package:robot_studio/presentation/shell/shell_shortcuts.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('shell shortcuts register palette, save, tabs, and layout chords', () {
    final map = ShellShortcutActivators.map;
    expect(map.values.whereType<OpenCommandPaletteIntent>(), isNotEmpty);
    expect(map.values.whereType<QuickOpenIntent>(), isNotEmpty);
    expect(map.values.whereType<SaveFileIntent>(), isNotEmpty);
    expect(map.values.whereType<SaveAllFilesIntent>(), isNotEmpty);
    expect(map.values.whereType<CloseActiveTabIntent>(), isNotEmpty);
    expect(map.values.whereType<ReopenClosedTabIntent>(), isNotEmpty);
    expect(map.values.whereType<NextEditorTabIntent>(), isNotEmpty);
    expect(map.values.whereType<ToggleSidebarIntent>(), isNotEmpty);
    expect(map.values.whereType<ToggleTerminalIntent>(), isNotEmpty);
    expect(map.values.whereType<FindInProjectIntent>(), isNotEmpty);
    expect(map.values.whereType<OpenSymbolsIntent>(), isNotEmpty);
    expect(map.values.whereType<FormatDocumentIntent>(), isNotEmpty);
    expect(map.values.whereType<ShowProblemsIntent>(), isNotEmpty);

    // Never bind a bare letter key (would steal typing).
    for (final activator in map.keys.whereType<SingleActivator>()) {
      final needsMod =
          activator.meta ||
          activator.control ||
          activator.alt ||
          activator.shift;
      expect(
        needsMod,
        isTrue,
        reason: 'activator $activator must require a modifier',
      );
    }
  });

  test('flutter Shortcuts only keep Ctrl+Tab cycling (menu owns the rest)', () {
    final flutter = ShellShortcutActivators.flutterShortcuts;
    expect(flutter.values.whereType<NextEditorTabIntent>(), isNotEmpty);
    expect(flutter.values.whereType<PreviousEditorTabIntent>(), isNotEmpty);
    expect(flutter.values.whereType<SaveFileIntent>(), isEmpty);
    expect(flutter.values.whereType<ToggleTerminalIntent>(), isEmpty);
  });

  test('robot editor shortcuts use VS Code delete-line chord', () {
    final builder = const RobotCodeShortcutsActivatorsBuilder();
    final deleteLine = builder.build(CodeShortcutType.lineDelete)!;
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    expect(
      deleteLine,
      contains(
        isMac
            ? const SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
                shift: true,
              )
            : const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
                shift: true,
              ),
      ),
    );
    // Default re_editor ⌘D / Ctrl+D must not remain (conflicts with multi-cursor).
    final plainD = deleteLine.whereType<SingleActivator>().any(
      (a) =>
          a.trigger == LogicalKeyboardKey.keyD &&
          (a.meta || a.control) &&
          !a.shift,
    );
    expect(plainD, isFalse);
  });

  test('robot editor shortcuts add Ctrl/Cmd+H for replace', () {
    final builder = const RobotCodeShortcutsActivatorsBuilder();
    final replace = builder.build(CodeShortcutType.replace)!;
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    expect(
      replace,
      contains(
        isMac
            ? const SingleActivator(LogicalKeyboardKey.keyH, meta: true)
            : const SingleActivator(LogicalKeyboardKey.keyH, control: true),
      ),
    );
  });
}
