import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';

void main() {
  testWidgets('toggle terminal token opens then collapses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpWithToken(int token) async {
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
    }

    // Initial token is ignored on first build (panel stays collapsed).
    await pumpWithToken(1);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    // Token change opens the panel (collapse control is arrow-down).
    await pumpWithToken(2);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    // Next change collapses again.
    await pumpWithToken(3);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
  });
}
