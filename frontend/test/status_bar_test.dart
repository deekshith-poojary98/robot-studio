import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';

void main() {
  testWidgets('status bar shows active environment versions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(
            projectName: 'robot-files',
            robotVersion: '7.4.2',
            pythonVersion: '3.13.9',
          ),
        ),
      ),
    );

    expect(find.text('ROBOT 7.4.2'), findsOneWidget);
    expect(find.text('PYTHON 3.13.9'), findsOneWidget);
    expect(find.text('ROBOT-FILES'), findsOneWidget);
    expect(find.textContaining('ENV '), findsNothing);
  });

  testWidgets('status bar hides version slots when no environment is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusBar()),
      ),
    );

    // Placeholder dashes read as broken indicators, so the slots are omitted.
    expect(find.textContaining('ROBOT'), findsNothing);
    expect(find.textContaining('PYTHON'), findsNothing);
    expect(find.text('NO PROJECT'), findsOneWidget);
  });
}
