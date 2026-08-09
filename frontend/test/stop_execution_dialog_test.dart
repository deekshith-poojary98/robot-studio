import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/execution/stop_execution_dialog.dart';

void main() {
  testWidgets('Stop dialog shows live progress and destructive Stop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = showStopExecutionDialog(
                  context,
                  suite: 'tests/sample.robot',
                  elapsedLabel: '12.4s',
                  liveSuite: 'sample',
                  liveTest: 'Hello',
                  liveKeyword: 'BuiltIn.Sleep',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Stop execution?'), findsOneWidget);
    expect(find.textContaining('report may be incomplete'), findsOneWidget);
    expect(find.text('Elapsed 12.4s'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('BuiltIn.Sleep'), findsOneWidget);
    expect(find.text('Keep running'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('Keep running dismisses without stopping', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = showStopExecutionDialog(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
