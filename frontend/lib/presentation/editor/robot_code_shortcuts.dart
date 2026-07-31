import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// VS Code–aligned activators on top of re_editor defaults.
///
/// Notable overrides:
/// - Delete Line → ⌘⇧K / Ctrl+Shift+K (re_editor default was ⌘D / Ctrl+D)
/// - Replace → also ⌘H / Ctrl+H (re_editor default was ⌘⌥F / Ctrl+Alt+F)
class RobotCodeShortcutsActivatorsBuilder
    extends CodeShortcutsActivatorsBuilder {
  const RobotCodeShortcutsActivatorsBuilder();

  static final _defaults = const DefaultCodeShortcutsActivatorsBuilder();

  static bool get _mac =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    switch (type) {
      case CodeShortcutType.lineDelete:
        return _mac
            ? const [
                SingleActivator(
                  LogicalKeyboardKey.keyK,
                  meta: true,
                  shift: true,
                ),
              ]
            : const [
                SingleActivator(
                  LogicalKeyboardKey.keyK,
                  control: true,
                  shift: true,
                ),
              ];
      case CodeShortcutType.replace:
        final base = _defaults.build(type) ?? const <ShortcutActivator>[];
        return [
          ...base,
          if (_mac)
            const SingleActivator(LogicalKeyboardKey.keyH, meta: true)
          else
            const SingleActivator(LogicalKeyboardKey.keyH, control: true),
        ];
      case CodeShortcutType.find:
        // Keep defaults; outer RobotCodeEditor Shortcuts also handle find.
        return _defaults.build(type);
      default:
        return _defaults.build(type);
    }
  }
}

/// Duplicate current / selected lines (VS Code Shift+Opt/Alt+↑/↓).
class CopyLineIntent extends Intent {
  const CopyLineIntent(this.direction);
  final VerticalDirection direction;
}
