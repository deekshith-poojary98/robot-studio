import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';

void main() {
  testWidgets('status bar shows active environment versions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(
            backendConnected: true,
            workspaceName: 'robot-files',
            robotVersion: '7.4.2',
            pythonVersion: '3.13',
            venvName: 'myenv',
          ),
        ),
      ),
    );

    expect(find.text('ROBOT 7.4.2'), findsOneWidget);
    expect(find.text('PYTHON 3.13'), findsOneWidget);
    expect(find.text('ENV myenv'), findsOneWidget);
  });

  testWidgets('status bar shows dashes when environment is missing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBar(backendConnected: true),
        ),
      ),
    );

    expect(find.text('ROBOT —'), findsOneWidget);
    expect(find.text('PYTHON —'), findsOneWidget);
    expect(find.text('ENV —'), findsOneWidget);
  });
}
