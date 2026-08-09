import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Shell-level intents (palette, tabs, layout) — not editor text editing.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

class QuickOpenIntent extends Intent {
  const QuickOpenIntent();
}

class SaveFileIntent extends Intent {
  const SaveFileIntent();
}

class SaveAllFilesIntent extends Intent {
  const SaveAllFilesIntent();
}

class CloseActiveTabIntent extends Intent {
  const CloseActiveTabIntent();
}

class ReopenClosedTabIntent extends Intent {
  const ReopenClosedTabIntent();
}

class NextEditorTabIntent extends Intent {
  const NextEditorTabIntent();
}

class PreviousEditorTabIntent extends Intent {
  const PreviousEditorTabIntent();
}

class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

class ToggleTerminalIntent extends Intent {
  const ToggleTerminalIntent();
}

class FindInProjectIntent extends Intent {
  const FindInProjectIntent();
}

class OpenSymbolsIntent extends Intent {
  /// Go to Symbol in Workspace (⌘/Ctrl+T).
  const OpenSymbolsIntent();
}

class FormatDocumentIntent extends Intent {
  const FormatDocumentIntent();
}

class ShowProblemsIntent extends Intent {
  const ShowProblemsIntent();
}

class RunFileIntent extends Intent {
  const RunFileIntent();
}

class StopExecutionIntent extends Intent {
  const StopExecutionIntent();
}

class ShowDoctorIntent extends Intent {
  const ShowDoctorIntent();
}

/// Platform-aware activators for Robot Studio chrome shortcuts.
///
/// Both macOS (⌘) and Win/Linux (Ctrl) chords are registered; the inactive
/// modifier simply never matches on that platform.
abstract final class ShellShortcutActivators {
  static bool get isMac =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Full chord catalog (docs / unit tests). Prefer [flutterShortcuts] inside
  /// [Shortcuts] — chords listed on [RobotStudioMenuBar] are owned by the
  /// platform and must not be dual-registered.
  static Map<ShortcutActivator, Intent> get map => <ShortcutActivator, Intent>{
    // Command Palette — VS Code ⌘/Ctrl+Shift+P; keep ⌘/Ctrl+K as alias.
    const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
        const OpenCommandPaletteIntent(),
    const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true):
        const OpenCommandPaletteIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
        const OpenCommandPaletteIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        const OpenCommandPaletteIntent(),

    // Quick Open (same palette — files are listed there).
    const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
        const QuickOpenIntent(),
    const SingleActivator(LogicalKeyboardKey.keyP, control: true):
        const QuickOpenIntent(),

    // Save
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
        const SaveFileIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const SaveFileIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
        const SaveAllFilesIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
        const SaveAllFilesIntent(),

    // Tabs
    const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
        const CloseActiveTabIntent(),
    const SingleActivator(LogicalKeyboardKey.keyW, control: true):
        const CloseActiveTabIntent(),
    const SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true):
        const ReopenClosedTabIntent(),
    const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true):
        const ReopenClosedTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true):
        const NextEditorTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
        const PreviousEditorTabIntent(),

    // Layout
    const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
        const ToggleSidebarIntent(),
    const SingleActivator(LogicalKeyboardKey.keyB, control: true):
        const ToggleSidebarIntent(),
    const SingleActivator(LogicalKeyboardKey.backquote, meta: true):
        const ToggleTerminalIntent(),
    const SingleActivator(LogicalKeyboardKey.backquote, control: true):
        const ToggleTerminalIntent(),

    // Search / Symbols / Problems / Format
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
        const FindInProjectIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
        const FindInProjectIntent(),
    const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
        const OpenSymbolsIntent(),
    const SingleActivator(LogicalKeyboardKey.keyT, control: true):
        const OpenSymbolsIntent(),
    const SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true):
        const ShowProblemsIntent(),
    const SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true):
        const ShowProblemsIntent(),
    // Shift+Option/Alt+F — Format Document
    const SingleActivator(LogicalKeyboardKey.keyF, shift: true, alt: true):
        const FormatDocumentIntent(),
  };

  /// Chords still handled by Flutter [Shortcuts] (not the native menu bar).
  ///
  /// Ctrl+Tab cycling is awkward as a platform menu accelerator on some hosts,
  /// so it stays here. Everything else with a menu equivalent lives on
  /// [RobotStudioMenuBar] items.
  static Map<ShortcutActivator, Intent> get flutterShortcuts =>
      <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            const NextEditorTabIntent(),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): const PreviousEditorTabIntent(),
      };

  /// Human-readable label for docs / palette (macOS vs Win/Linux).
  static String label(String mac, String other) => isMac ? mac : other;
}
