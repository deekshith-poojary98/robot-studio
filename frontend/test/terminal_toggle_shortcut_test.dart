import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';

void main() {
  testWidgets('toggle terminal token opens then collapses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var token = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(
                workingDirectory: '/tmp/proj',
                toggleTerminalToken: token,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TERMINAL'), findsWidgets);

    token = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(
                workingDirectory: '/tmp/proj',
                toggleTerminalToken: token,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Collapsed bar shows the active tab label.
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
  });
}
