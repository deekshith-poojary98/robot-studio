import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'shell_shortcuts.dart';

/// Callbacks + enablement for the native window menu bar (VS Code–style).
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
    required this.onShowSymbols,
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
  final VoidCallback onShowSymbols;
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

/// Native title-bar menus (macOS menu bar / Windows·Linux window menu).
///
/// Shortcuts on [PlatformMenuItem]s are owned by the platform — do **not** also
/// register the same chords in a [Shortcuts] widget or they fire twice.
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

  static SingleActivator _mod(LogicalKeyboardKey key, {bool shift = false}) =>
      isMac
          ? SingleActivator(key, meta: true, shift: shift)
          : SingleActivator(key, control: true, shift: shift);

  @override
  Widget build(BuildContext context) {
    final a = actions;
    return PlatformMenuBar(
      menus: [
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
                      : 'Reveal in File Manager',
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
                // Find / Replace chords stay on the editor (re_editor) so they
                // keep working in widget tests and don't double-fire with the
                // platform menu shortcut table.
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
                  label: 'Symbols',
                  onSelected: a.hasWorkspace ? a.onShowSymbols : null,
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
                  onSelected:
                      a.hasWorkspace ? a.onFindSymbolInProject : null,
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
              onSelected:
                  a.hasActiveFile && a.hasWorkspace && a.canRun
                      ? a.onRunFile
                      : null,
            ),
            PlatformMenuItem(
              label: 'Run Project',
              onSelected: a.hasWorkspace && a.canRun ? a.onRunProject : null,
            ),
            PlatformMenuItem(
              label: 'Stop',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.f5,
                shift: true,
              ),
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
      ],
      child: child,
    );
  }
}
