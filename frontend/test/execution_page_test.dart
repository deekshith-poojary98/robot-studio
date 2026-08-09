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
    expect(find.text('Now Running'), findsOneWidget);
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

    expect(find.textContaining('toolbar or Tests'), findsOneWidget);
    expect(find.text('IDLE'), findsNothing);
    expect(find.textContaining('Suite → test → keyword'), findsOneWidget);
  });

  testWidgets('Now Running shows live suite test and keyword', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: [],
            status: ExecutionStatus.running,
            currentRun: null,
            liveSuite: 'Demo',
            liveTest: 'Hello',
            liveKeyword: 'BuiltIn.Log',
            elapsedLabel: '0:12',
          ),
        ),
      ),
    );

    expect(find.text('Now Running'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('BuiltIn.Log'), findsOneWidget);
    expect(find.text('KEYWORD'), findsOneWidget);
  });

  testWidgets('idle with last progress shows Last location', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExecutionPage(
            consoleLines: [],
            status: ExecutionStatus.finished,
            currentRun: null,
            liveSuite: 'Login',
            liveTest: 'Login with valid creds',
            liveKeyword: 'BuiltIn.Fail',
          ),
        ),
      ),
    );

    expect(find.text('Last location'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.textContaining('most recent run'), findsOneWidget);
  });
}
