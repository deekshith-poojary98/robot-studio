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

  testWidgets(
    'auto-opens Problems when diagnostics appear and auto-closes when cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const problem = DiagnosticInfo(
        severity: DiagnosticSeverity.error,
        filePath: '/tmp/demo.robot',
        line: 4,
        column: 2,
        message: 'Unknown keyword',
      );

      Widget host({required List<DiagnosticInfo> problems}) {
        return MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                BottomPanel(problems: problems, problemCount: problems.length),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(host(problems: const []));
      await tester.pump();
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.text('Unknown keyword'), findsNothing);

      await tester.pumpWidget(host(problems: const [problem]));
      await tester.pumpAndSettle();
      expect(find.text('Unknown keyword'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      await tester.pumpWidget(host(problems: const []));
      await tester.pumpAndSettle();
      expect(find.text('Unknown keyword'), findsNothing);
      expect(find.text('No problems'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    },
  );

  testWidgets('does not auto-close Problems when the user opened it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const problem = DiagnosticInfo(
      severity: DiagnosticSeverity.error,
      filePath: '/tmp/demo.robot',
      line: 4,
      column: 2,
      message: 'Unknown keyword',
    );

    Widget host({
      required List<DiagnosticInfo> problems,
      int? revealProblemsToken,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(
                problems: problems,
                problemCount: problems.length,
                revealProblemsToken: revealProblemsToken,
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(host(problems: const []));
    await tester.pump();

    await tester.pumpWidget(host(problems: const [], revealProblemsToken: 1));
    await tester.pumpAndSettle();
    expect(find.text('No problems'), findsOneWidget);

    await tester.pumpWidget(
      host(problems: const [problem], revealProblemsToken: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unknown keyword'), findsOneWidget);

    await tester.pumpWidget(host(problems: const [], revealProblemsToken: 1));
    await tester.pumpAndSettle();
    expect(find.text('No problems'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('does not auto-close Problems opened from the collapsed bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const problem = DiagnosticInfo(
      severity: DiagnosticSeverity.warning,
      filePath: '/tmp/demo.robot',
      line: 1,
      column: 1,
      message: 'Unused variable',
    );

    Widget host({required List<DiagnosticInfo> problems}) {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(problems: problems, problemCount: problems.length),
            ],
          ),
        ),
      );
    }

    // First frame with problems stays collapsed (auto-open is 0 → N only).
    await tester.pumpWidget(host(problems: const [problem]));
    await tester.pump();
    expect(find.text('PROBLEMS 1'), findsOneWidget);

    await tester.tap(find.text('PROBLEMS 1'));
    await tester.pumpAndSettle();
    expect(find.text('Unused variable'), findsOneWidget);

    await tester.pumpWidget(host(problems: const []));
    await tester.pumpAndSettle();
    expect(find.text('No problems'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
  });

  testWidgets('does not auto-close after the user switches to Terminal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const problem = DiagnosticInfo(
      severity: DiagnosticSeverity.error,
      filePath: '/tmp/demo.robot',
      line: 4,
      column: 2,
      message: 'Unknown keyword',
    );

    Widget host({required List<DiagnosticInfo> problems}) {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              BottomPanel(problems: problems, problemCount: problems.length),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(host(problems: const []));
    await tester.pump();
    await tester.pumpWidget(host(problems: const [problem]));
    await tester.pumpAndSettle();
    expect(find.text('Unknown keyword'), findsOneWidget);

    await tester.tap(find.text('TERMINAL'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(problems: const []));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.text('No problems'), findsNothing);
  });
}
