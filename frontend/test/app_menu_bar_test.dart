import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
      onCloseProject: () {},
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
      onPreferences: () {},
      onCommandPalette: () {},
      onQuickOpen: () {},
      onToggleSidebar: () {},
      onToggleTerminal: () {},
      onShowProblems: () {},
      onShowExplorer: () {},
      onShowSearch: () {},
      onShowLibraries: () {},
      onShowInsights: () {},
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

  Future<void> withPlatform(
    TargetPlatform platform,
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  }

  testWidgets('macOS PlatformMenuBar exposes File Edit View Go Run Terminal', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.macOS, tester, () async {
      await tester.pumpWidget(
        RobotStudioMenuBar(actions: actions(), child: const SizedBox.expand()),
      );

      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final labels = bar.menus
          .map((menu) => (menu as PlatformMenu).label)
          .toList();

      expect(labels.first, 'Robot Studio');
      expect(
        labels,
        containsAll(['File', 'Edit', 'View', 'Go', 'Run', 'Terminal']),
      );
    });
  });

  testWidgets('Windows MenuBar exposes File Edit View Go Run Terminal', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RobotStudioMenuBar(
              actions: actions(),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      expect(find.byType(MenuBar), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.byType(PlatformMenuBar), findsNothing);
    });
  });

  testWidgets('Save is disabled when no file is open (macOS)', (tester) async {
    await withPlatform(TargetPlatform.macOS, tester, () async {
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
  });

  testWidgets('Windows Close Project is disabled when no workspace', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, tester, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RobotStudioMenuBar(
              actions: actions(hasWorkspace: false),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();

      final close = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Close Project'),
      );
      expect(close.onPressed, isNull);
    });
  });

  testWidgets('Windows Close Project invokes callback when enabled', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, tester, () async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RobotStudioMenuBar(
              actions: AppMenuBarActions(
                hasActiveFile: true,
                hasOpenTabs: true,
                hasWorkspace: true,
                wordWrap: true,
                canStop: false,
                onNewProject: () {},
                onOpenProject: () {},
                onOpenWorkspace: () {},
                onCloseProject: () => closed = true,
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
                onPreferences: () {},
                onCommandPalette: () {},
                onQuickOpen: () {},
                onToggleSidebar: () {},
                onToggleTerminal: () {},
                onShowProblems: () {},
                onShowExplorer: () {},
                onShowSearch: () {},
                onShowLibraries: () {},
                onShowInsights: () {},
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
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Close Project'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  });
}
