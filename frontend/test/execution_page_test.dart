import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/execution_info.dart';
import 'package:robot_studio/presentation/execution/execution_page.dart';

void main() {
  testWidgets('Execution page monitors without launch buttons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: ['[log] hello'],
            status: ExecutionStatus.running,
            currentRun: null,
          ),
        ),
      ),
    );

    expect(find.text('Execution'), findsOneWidget);
    expect(find.text('Live Output'), findsOneWidget);
    expect(find.text('Recent Runs'), findsNothing);
    expect(find.textContaining('RUNNING'), findsNothing);
    expect(find.text('FINISHED'), findsNothing);
    expect(find.text('Run File'), findsNothing);
    expect(find.text('Run Project'), findsNothing);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('[log] hello'), findsOneWidget);
  });

  testWidgets('idle Execution page shows monitoring copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: [],
            status: ExecutionStatus.idle,
            currentRun: null,
          ),
        ),
      ),
    );

    expect(find.textContaining('toolbar or Test Explorer'), findsOneWidget);
    expect(find.text('IDLE'), findsNothing);
  });
}
