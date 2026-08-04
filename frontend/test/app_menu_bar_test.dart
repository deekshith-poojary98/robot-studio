import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/shell/app_menu_bar.dart';

void main() {
  AppMenuBarActions actions({
    bool hasActiveFile = true,
    bool hasWorkspace = true,
  }) {
    return AppMenuBarActions(
      hasActiveFile: hasActiveFile,
      hasOpenTabs: hasActiveFile,
      hasWorkspace: hasWorkspace,
      wordWrap: true,
      canStop: false,
      onNewProject: () {},
      onOpenProject: () {},
      onOpenWorkspace: () {},
      onSave: () {},
      onSaveAll: () {},
      onCloseEditor: () {},
      onReopenClosedEditor: () {},
      onRevealInFolder: () {},
      onFind: () {},
      onReplace: () {},
      onFindInProject: () {},
      onFormatDocument: () {},
      onFormatSelection: () {},
      onToggleWordWrap: () {},
      onCommandPalette: () {},
      onQuickOpen: () {},
      onToggleSidebar: () {},
      onToggleTerminal: () {},
      onShowProblems: () {},
      onShowExplorer: () {},
      onShowSearch: () {},
      onShowLibraries: () {},
      onShowSymbols: () {},
      onShowSourceControl: () {},
      onShowTests: () {},
      onShowReports: () {},
      onShowDoctor: () {},
      onGoToDefinition: () {},
      onPeekDefinition: () {},
      onFindReferences: () {},
      onGoToSymbolInFile: () {},
      onFindSymbolInProject: () {},
      onShowHover: () {},
      onRunFile: () {},
      onRunProject: () {},
      onStop: () {},
    );
  }

  testWidgets('menu bar exposes File Edit View Go Run Terminal', (tester) async {
    await tester.pumpWidget(
      RobotStudioMenuBar(
        actions: actions(),
        child: const SizedBox.expand(),
      ),
    );

    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final labels = bar.menus.map((menu) => (menu as PlatformMenu).label).toList();

    expect(labels, containsAll(['File', 'Edit', 'View', 'Go', 'Run', 'Terminal']));
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      expect(labels.first, 'Robot Studio');
    }
  });

  testWidgets('Save is disabled when no file is open', (tester) async {
    await tester.pumpWidget(
      RobotStudioMenuBar(
        actions: actions(hasActiveFile: false),
        child: const SizedBox.expand(),
      ),
    );

    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    PlatformMenuItem? save;
    for (final root in bar.menus.whereType<PlatformMenu>()) {
      for (final entry in root.menus) {
        if (entry is PlatformMenuItemGroup) {
          for (final item in entry.members.whereType<PlatformMenuItem>()) {
            if (item.label == 'Save') save = item;
          }
        } else if (entry.label == 'Save') {
          save = entry;
        }
      }
    }

    expect(save, isNotNull);
    expect(save!.onSelected, isNull);
    expect(save.shortcut, isA<SingleActivator>());
  });
}
