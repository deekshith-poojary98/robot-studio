import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';
import 'package:robot_studio/presentation/panels/terminal_panel.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('terminal tab shows empty state without project', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Starts collapsed; reveal token only applies when it *changes*.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              BottomPanel(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              BottomPanel(revealTerminalToken: 1),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TERMINAL'), findsWidgets);
    expect(find.text('No project open'), findsOneWidget);
    expect(find.byType(TerminalPanel), findsOneWidget);
  });

  testWidgets('Windows uses the focused hardware keyboard path', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SizedBox(
              height: 240,
              child: TerminalPanel(workingDirectory: 'C:\\project'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.hardwareKeyboardOnly, isTrue);
      expect(view.autofocus, isTrue);
      expect(view.focusNode, isNotNull);
      expect(view.focusNode!.hasFocus, isTrue);
      expect(view.textStyle.fontFamily, 'Consolas');
      expect(view.textScaler, TextScaler.noScaling);
      expect(view.padding, EdgeInsets.zero);

      final output = <String>[];
      view.terminal.onOutput = output.add;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

      expect(output.join(), 'a');
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('macOS keeps the IME-capable text input path', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SizedBox(
              height: 240,
              child: TerminalPanel(workingDirectory: '/project'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(view.hardwareKeyboardOnly, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('clicking the terminal restores keyboard focus', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              TextField(key: Key('other-control')),
              Expanded(child: TerminalPanel(workingDirectory: 'C:\\project')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    final terminalFocus = view.focusNode!;
    expect(terminalFocus.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('other-control')));
    await tester.pump();
    expect(terminalFocus.hasFocus, isFalse);

    await tester.tap(find.byType(TerminalView));
    await tester.pump(const Duration(milliseconds: 350));
    expect(terminalFocus.hasFocus, isTrue);
  });

  testWidgets('focus follows terminal tab visibility', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<FocusNode> pumpPanel({required bool visible}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: TerminalPanel(
              workingDirectory: 'C:\\project',
              isVisible: visible,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<TerminalView>(find.byType(TerminalView)).focusNode!;
    }

    final terminalFocus = await pumpPanel(visible: false);
    expect(terminalFocus.hasFocus, isFalse);

    final sameFocus = await pumpPanel(visible: true);
    expect(identical(sameFocus, terminalFocus), isTrue);
    expect(sameFocus.hasFocus, isTrue);
  });
}
