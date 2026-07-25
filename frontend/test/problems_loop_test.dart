import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/presentation/panels/bottom_panel.dart';
import 'package:robot_studio/presentation/shell/status_bar.dart';

void main() {
  testWidgets('diagnostic locationLabel uses file basename', (tester) async {
    const item = DiagnosticInfo(
      severity: DiagnosticSeverity.error,
      filePath: '/Users/demo/project/tests/sample.robot',
      line: 12,
      column: 5,
      message: 'Unknown keyword',
    );
    expect(item.locationLabel, 'sample.robot:12:5');
  });

  testWidgets('status bar errors open problems callback', (tester) async {
    var tapped = false;
    await tester.binding.setSurfaceSize(const Size(1200, 80));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBar(
            errorCount: 2,
            warningCount: 1,
            onProblemsTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('ERRORS 2'), findsOneWidget);
    await tester.tap(find.text('ERRORS 2'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('bottom panel reveals Problems on token', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedLine = 0;
    const problems = [
      DiagnosticInfo(
        severity: DiagnosticSeverity.error,
        filePath: '/tmp/demo.robot',
        line: 4,
        column: 2,
        message: 'Unknown keyword',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(
                problems: problems,
                problemCount: 1,
                onProblemSelected: (item) => selectedLine = item.line,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Collapsed initially — bump token via rebuild.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(
                problems: problems,
                problemCount: 1,
                revealProblemsToken: 1,
                onProblemSelected: (item) => selectedLine = item.line,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unknown keyword'), findsOneWidget);
    await tester.tap(find.text('Unknown keyword'));
    await tester.pump();
    expect(selectedLine, 4);
  });

  testWidgets('collapsed bar shows problems shortcut', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              BottomPanel(
                problems: [
                  DiagnosticInfo(
                    severity: DiagnosticSeverity.warning,
                    filePath: '/tmp/demo.robot',
                    line: 1,
                    column: 1,
                    message: 'Unused variable',
                  ),
                ],
                problemCount: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PROBLEMS 1'), findsOneWidget);
    await tester.tap(find.text('PROBLEMS 1'));
    await tester.pumpAndSettle();
    expect(find.text('Unused variable'), findsOneWidget);
  });
}
