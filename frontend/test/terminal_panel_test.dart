import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';
import 'package:robot_studio/presentation/panels/terminal_panel.dart';

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
}
