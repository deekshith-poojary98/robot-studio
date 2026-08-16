import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'shell_shortcuts.dart';

/// Callbacks + enablement for the window menu bar (VS Code–style).
class AppMenuBarActions {
  const AppMenuBarActions({
    required this.hasActiveFile,
    required this.hasOpenTabs,
    required this.hasWorkspace,
    required this.wordWrap,
    required this.canStop,
    this.canRun = true,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onOpenWorkspace,
    required this.onCloseProject,
    required this.onSave,
    required this.onSaveAll,
    required this.onCloseEditor,
    required this.onReopenClosedEditor,
    required this.onRevealInFolder,
    required this.onFind,
    required this.onReplace,
    required this.onFindInProject,
    required this.onFormatDocument,
    required this.onFormatSelection,
    required this.onToggleWordWrap,
    required this.onPreferences,
    required this.onCommandPalette,
    required this.onQuickOpen,
    required this.onToggleSidebar,
    required this.onToggleTerminal,
    required this.onShowProblems,
    required this.onShowExplorer,
    required this.onShowSearch,
    required this.onShowLibraries,
    required this.onShowInsights,
    required this.onShowSourceControl,
    required this.onShowTests,
    required this.onShowReports,
    required this.onShowDoctor,
    required this.onGoToDefinition,
    required this.onPeekDefinition,
    required this.onFindReferences,
    required this.onGoToSymbolInFile,
    required this.onFindSymbolInProject,
    required this.onShowHover,
    required this.onRunFile,
    required this.onRunProject,
    required this.onStop,
  });

  final bool hasActiveFile;
  final bool hasOpenTabs;
  final bool hasWorkspace;
  final bool wordWrap;
  final bool canStop;
  final bool canRun;

  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback onOpenWorkspace;
  final VoidCallback onCloseProject;
  final VoidCallback onSave;
  final VoidCallback onSaveAll;
  final VoidCallback onCloseEditor;
  final VoidCallback onReopenClosedEditor;
  final VoidCallback onRevealInFolder;
  final VoidCallback onFind;
  final VoidCallback onReplace;
  final VoidCallback onFindInProject;
  final VoidCallback onFormatDocument;
  final VoidCallback onFormatSelection;
  final VoidCallback onToggleWordWrap;
  final VoidCallback onPreferences;
  final VoidCallback onCommandPalette;
  final VoidCallback onQuickOpen;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleTerminal;
  final VoidCallback onShowProblems;
  final VoidCallback onShowExplorer;
  final VoidCallback onShowSearch;
  final VoidCallback onShowLibraries;
  final VoidCallback onShowInsights;
  final VoidCallback onShowSourceControl;
  final VoidCallback onShowTests;
  final VoidCallback onShowReports;
  final VoidCallback onShowDoctor;
  final VoidCallback onGoToDefinition;
  final VoidCallback onPeekDefinition;
  final VoidCallback onFindReferences;
  final VoidCallback onGoToSymbolInFile;
  final VoidCallback onFindSymbolInProject;
  final VoidCallback onShowHover;
  final VoidCallback onRunFile;
  final VoidCallback onRunProject;
  final VoidCallback onStop;
}

/// Application menus: native [PlatformMenuBar] on macOS; in-window Material
/// [MenuBar] on Windows / Linux (Flutter has no built-in native menus there).
///
/// On macOS, shortcuts on [PlatformMenuItem]s are owned by the platform — do
/// **not** also register those chords in [Shortcuts] or they fire twice. On
/// Windows / Linux, [ShellShortcutActivators.flutterShortcuts] owns the chords.
class RobotStudioMenuBar extends StatelessWidget {
  const RobotStudioMenuBar({
    super.key,
    required this.actions,
    required this.child,
  });

  final AppMenuBarActions actions;
  final Widget child;

  static bool get isMac =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// True when we paint File / Edit / … inside the window (Win / Linux / web).
  static bool get usesInWindowMenu => !isMac;

  static SingleActivator _mod(LogicalKeyboardKey key, {bool shift = false}) =>
      isMac
      ? SingleActivator(key, meta: true, shift: shift)
      : SingleActivator(key, control: true, shift: shift);

  @override
  Widget build(BuildContext context) {
    if (isMac) {
      return PlatformMenuBar(menus: _platformMenus(actions), child: child);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InWindowMenuBar(actions: actions),
        Expanded(child: child),
      ],
    );
  }

  List<PlatformMenuItem> _platformMenus(AppMenuBarActions a) {
    return [
      if (isMac)
        PlatformMenu(
          label: 'Robot Studio',
          menus: [
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.about,
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.quit,
                ),
              ],
            ),
          ],
        ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'New Project…',
                onSelected: a.onNewProject,
              ),
              PlatformMenuItem(
                label: 'Open Project…',
                onSelected: a.onOpenProject,
              ),
              PlatformMenuItem(
                label: 'Open Workspace…',
                onSelected: a.onOpenWorkspace,
              ),
              PlatformMenuItem(
                label: 'Close Project',
                onSelected: a.hasWorkspace ? a.onCloseProject : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Save',
                shortcut: _mod(LogicalKeyboardKey.keyS),
                onSelected: a.hasActiveFile ? a.onSave : null,
              ),
              PlatformMenuItem(
                label: 'Save All',
                shortcut: _mod(LogicalKeyboardKey.keyS, shift: true),
                onSelected: a.hasOpenTabs ? a.onSaveAll : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Settings…',
                shortcut: _mod(LogicalKeyboardKey.comma),
                onSelected: a.onPreferences,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Close Editor',
                shortcut: _mod(LogicalKeyboardKey.keyW),
                onSelected: a.hasActiveFile ? a.onCloseEditor : null,
              ),
              PlatformMenuItem(
                label: 'Reopen Closed Editor',
                shortcut: _mod(LogicalKeyboardKey.keyT, shift: true),
                onSelected: a.onReopenClosedEditor,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: ShellShortcutActivators.isMac
                    ? 'Reveal in Finder'
                    : 'Reveal in File Explorer',
                onSelected: a.hasActiveFile ? a.onRevealInFolder : null,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Find…',
                onSelected: a.hasActiveFile ? a.onFind : null,
              ),
              PlatformMenuItem(
                label: 'Replace…',
                onSelected: a.hasActiveFile ? a.onReplace : null,
              ),
              PlatformMenuItem(
                label: 'Find in Project…',
                shortcut: _mod(LogicalKeyboardKey.keyF, shift: true),
                onSelected: a.hasWorkspace ? a.onFindInProject : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Format Document',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  shift: true,
                  alt: true,
                ),
                onSelected: a.hasActiveFile ? a.onFormatDocument : null,
              ),
              PlatformMenuItem(
                label: 'Format Selection',
                onSelected: a.hasActiveFile ? a.onFormatSelection : null,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: a.wordWrap ? 'Word Wrap ✓' : 'Word Wrap',
                onSelected: a.onToggleWordWrap,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Command Palette…',
                shortcut: _mod(LogicalKeyboardKey.keyP, shift: true),
                onSelected: a.onCommandPalette,
              ),
              PlatformMenuItem(
                label: 'Go to File…',
                shortcut: _mod(LogicalKeyboardKey.keyP),
                onSelected: a.onQuickOpen,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Explorer',
                onSelected: a.hasWorkspace ? a.onShowExplorer : null,
              ),
              PlatformMenuItem(
                label: 'Search',
                onSelected: a.hasWorkspace ? a.onShowSearch : null,
              ),
              PlatformMenuItem(
                label: 'Libraries',
                onSelected: a.hasWorkspace ? a.onShowLibraries : null,
              ),
              PlatformMenuItem(
                label: 'Insights',
                onSelected: a.hasWorkspace ? a.onShowInsights : null,
              ),
              PlatformMenuItem(
                label: 'Source Control',
                onSelected: a.hasWorkspace ? a.onShowSourceControl : null,
              ),
              PlatformMenuItem(
                label: 'Tests',
                onSelected: a.hasWorkspace ? a.onShowTests : null,
              ),
              PlatformMenuItem(
                label: 'Reports',
                onSelected: a.hasWorkspace ? a.onShowReports : null,
              ),
              PlatformMenuItem(
                label: 'Robot Doctor',
                shortcut: _mod(LogicalKeyboardKey.keyD, shift: true),
                onSelected: a.hasWorkspace ? a.onShowDoctor : null,
              ),
              PlatformMenuItem(
                label: 'Problems',
                shortcut: _mod(LogicalKeyboardKey.keyM, shift: true),
                onSelected: a.onShowProblems,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Toggle Side Bar',
                shortcut: _mod(LogicalKeyboardKey.keyB),
                onSelected: a.onToggleSidebar,
              ),
              PlatformMenuItem(
                label: 'Toggle Terminal',
                onSelected: a.onToggleTerminal,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Go',
        menus: [
          PlatformMenuItem(
            label: 'Go to Definition',
            onSelected: a.hasActiveFile ? a.onGoToDefinition : null,
          ),
          PlatformMenuItem(
            label: 'Peek Definition',
            onSelected: a.hasActiveFile ? a.onPeekDefinition : null,
          ),
          PlatformMenuItem(
            label: 'Find References',
            onSelected: a.hasActiveFile ? a.onFindReferences : null,
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Go to Symbol in File…',
                onSelected: a.hasActiveFile ? a.onGoToSymbolInFile : null,
              ),
              PlatformMenuItem(
                label: 'Find Symbol in Project…',
                shortcut: _mod(LogicalKeyboardKey.keyT),
                onSelected: a.hasWorkspace ? a.onFindSymbolInProject : null,
              ),
              PlatformMenuItem(
                label: 'Show Hover Info',
                onSelected: a.hasActiveFile ? a.onShowHover : null,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Run',
        menus: [
          PlatformMenuItem(
            label: 'Run File',
            shortcut: const SingleActivator(LogicalKeyboardKey.f5),
            onSelected: a.hasActiveFile && a.hasWorkspace && a.canRun
                ? a.onRunFile
                : null,
          ),
          PlatformMenuItem(
            label: 'Run Project',
            onSelected: a.hasWorkspace && a.canRun ? a.onRunProject : null,
          ),
          PlatformMenuItem(
            label: 'Stop',
            shortcut: const SingleActivator(LogicalKeyboardKey.f5, shift: true),
            onSelected: a.canStop ? a.onStop : null,
          ),
        ],
      ),
      PlatformMenu(
        label: 'Terminal',
        menus: [
          PlatformMenuItem(
            label: 'Toggle Terminal',
            shortcut: _mod(LogicalKeyboardKey.backquote),
            onSelected: a.onToggleTerminal,
          ),
        ],
      ),
    ];
  }
}

class _InWindowMenuBar extends StatelessWidget {
  const _InWindowMenuBar({required this.actions});

  final AppMenuBarActions actions;

  static SingleActivator _ctrl(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, control: true, shift: shift);

  @override
  Widget build(BuildContext context) {
    final a = actions;
    final palette = context.palette;
    return Material(
      color: palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.borderSubtle)),
        ),
        child: MenuBar(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(palette.surface),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
          ),
          children: [
            SubmenuButton(
              menuChildren: [
                _item('New Project…', onPressed: a.onNewProject),
                _item('Open Project…', onPressed: a.onOpenProject),
                _item('Open Workspace…', onPressed: a.onOpenWorkspace),
                _item(
                  'Close Project',
                  onPressed: a.hasWorkspace ? a.onCloseProject : null,
                ),
                const Divider(height: 8),
                _item(
                  'Save',
                  shortcut: _ctrl(LogicalKeyboardKey.keyS),
                  onPressed: a.hasActiveFile ? a.onSave : null,
                ),
                _item(
                  'Save All',
                  shortcut: _ctrl(LogicalKeyboardKey.keyS, shift: true),
                  onPressed: a.hasOpenTabs ? a.onSaveAll : null,
                ),
                const Divider(height: 8),
                _item(
                  'Settings…',
                  shortcut: _ctrl(LogicalKeyboardKey.comma),
                  onPressed: a.onPreferences,
                ),
                const Divider(height: 8),
                _item(
                  'Close Editor',
                  shortcut: _ctrl(LogicalKeyboardKey.keyW),
                  onPressed: a.hasActiveFile ? a.onCloseEditor : null,
                ),
                _item(
                  'Reopen Closed Editor',
                  shortcut: _ctrl(LogicalKeyboardKey.keyT, shift: true),
                  onPressed: a.onReopenClosedEditor,
                ),
                const Divider(height: 8),
                _item(
                  'Reveal in File Explorer',
                  onPressed: a.hasActiveFile ? a.onRevealInFolder : null,
                ),
              ],
              child: const Text('File'),
            ),
            SubmenuButton(
              menuChildren: [
                _item('Find…', onPressed: a.hasActiveFile ? a.onFind : null),
                _item(
                  'Replace…',
                  onPressed: a.hasActiveFile ? a.onReplace : null,
                ),
                _item(
                  'Find in Project…',
                  shortcut: _ctrl(LogicalKeyboardKey.keyF, shift: true),
                  onPressed: a.hasWorkspace ? a.onFindInProject : null,
                ),
                const Divider(height: 8),
                _item(
                  'Format Document',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    shift: true,
                    alt: true,
                  ),
                  onPressed: a.hasActiveFile ? a.onFormatDocument : null,
                ),
                _item(
                  'Format Selection',
                  onPressed: a.hasActiveFile ? a.onFormatSelection : null,
                ),
                const Divider(height: 8),
                _item(
                  a.wordWrap ? 'Word Wrap ✓' : 'Word Wrap',
                  onPressed: a.onToggleWordWrap,
                ),
              ],
              child: const Text('Edit'),
            ),
            SubmenuButton(
              menuChildren: [
                _item(
                  'Command Palette…',
                  shortcut: _ctrl(LogicalKeyboardKey.keyP, shift: true),
                  onPressed: a.onCommandPalette,
                ),
                _item(
                  'Go to File…',
                  shortcut: _ctrl(LogicalKeyboardKey.keyP),
                  onPressed: a.onQuickOpen,
                ),
                const Divider(height: 8),
                _item(
                  'Explorer',
                  onPressed: a.hasWorkspace ? a.onShowExplorer : null,
                ),
                _item(
                  'Search',
                  onPressed: a.hasWorkspace ? a.onShowSearch : null,
                ),
                _item(
                  'Libraries',
                  onPressed: a.hasWorkspace ? a.onShowLibraries : null,
                ),
                _item(
                  'Insights',
                  onPressed: a.hasWorkspace ? a.onShowInsights : null,
                ),
                _item(
                  'Source Control',
                  onPressed: a.hasWorkspace ? a.onShowSourceControl : null,
                ),
                _item(
                  'Tests',
                  onPressed: a.hasWorkspace ? a.onShowTests : null,
                ),
                _item(
                  'Reports',
                  onPressed: a.hasWorkspace ? a.onShowReports : null,
                ),
                _item(
                  'Robot Doctor',
                  shortcut: _ctrl(LogicalKeyboardKey.keyD, shift: true),
                  onPressed: a.hasWorkspace ? a.onShowDoctor : null,
                ),
                _item(
                  'Problems',
                  shortcut: _ctrl(LogicalKeyboardKey.keyM, shift: true),
                  onPressed: a.onShowProblems,
                ),
                const Divider(height: 8),
                _item(
                  'Toggle Side Bar',
                  shortcut: _ctrl(LogicalKeyboardKey.keyB),
                  onPressed: a.onToggleSidebar,
                ),
                _item('Toggle Terminal', onPressed: a.onToggleTerminal),
              ],
              child: const Text('View'),
            ),
            SubmenuButton(
              menuChildren: [
                _item(
                  'Go to Definition',
                  onPressed: a.hasActiveFile ? a.onGoToDefinition : null,
                ),
                _item(
                  'Peek Definition',
                  onPressed: a.hasActiveFile ? a.onPeekDefinition : null,
                ),
                _item(
                  'Find References',
                  onPressed: a.hasActiveFile ? a.onFindReferences : null,
                ),
                const Divider(height: 8),
                _item(
                  'Go to Symbol in File…',
                  onPressed: a.hasActiveFile ? a.onGoToSymbolInFile : null,
                ),
                _item(
                  'Find Symbol in Project…',
                  shortcut: _ctrl(LogicalKeyboardKey.keyT),
                  onPressed: a.hasWorkspace ? a.onFindSymbolInProject : null,
                ),
                _item(
                  'Show Hover Info',
                  onPressed: a.hasActiveFile ? a.onShowHover : null,
                ),
              ],
              child: const Text('Go'),
            ),
            SubmenuButton(
              menuChildren: [
                _item(
                  'Run File',
                  shortcut: const SingleActivator(LogicalKeyboardKey.f5),
                  onPressed: a.hasActiveFile && a.hasWorkspace && a.canRun
                      ? a.onRunFile
                      : null,
                ),
                _item(
                  'Run Project',
                  onPressed: a.hasWorkspace && a.canRun ? a.onRunProject : null,
                ),
                _item(
                  'Stop',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.f5,
                    shift: true,
                  ),
                  onPressed: a.canStop ? a.onStop : null,
                ),
              ],
              child: const Text('Run'),
            ),
            SubmenuButton(
              menuChildren: [
                _item(
                  'Toggle Terminal',
                  shortcut: _ctrl(LogicalKeyboardKey.backquote),
                  onPressed: a.onToggleTerminal,
                ),
              ],
              child: const Text('Terminal'),
            ),
          ],
        ),
      ),
    );
  }

  static MenuItemButton _item(
    String label, {
    VoidCallback? onPressed,
    MenuSerializableShortcut? shortcut,
  }) {
    return MenuItemButton(
      onPressed: onPressed,
      shortcut: shortcut,
      child: Text(label),
    );
  }
}
