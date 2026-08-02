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

    final project = tester.getTopLeft(find.text('ROBOT-FILES'));
    final robot = tester.getTopLeft(find.text('ROBOT 7.4.2'));
    final python = tester.getTopLeft(find.text('PYTHON 3.13.9'));
    expect(robot.dx, greaterThan(project.dx));
    expect(python.dx, greaterThan(robot.dx));
    final barWidth = tester.getSize(find.byType(StatusBar)).width;
    expect(tester.getTopRight(find.text('PYTHON 3.13.9')).dx, lessThan(barWidth));
    expect(
      barWidth - tester.getTopRight(find.text('PYTHON 3.13.9')).dx,
      lessThan(24),
    );
    expect(find.text('BACKEND UNAVAILABLE'), findsNothing);
  });

  testWidgets('status bar shows backend unavailable when offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(backendUnavailable: true),
        ),
      ),
    );

    expect(find.text('BACKEND UNAVAILABLE'), findsOneWidget);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('CONNECTED'), findsNothing);
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
