import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/presentation/panels/problems_panel.dart';

void main() {
  testWidgets('ProblemsPanel shows diagnostics and handles click', (
    WidgetTester tester,
  ) async {
    DiagnosticInfo? selected;
    const diagnostics = [
      DiagnosticInfo(
        severity: DiagnosticSeverity.error,
        filePath: '/tmp/demo.robot',
        line: 3,
        column: 1,
        message: 'Unknown keyword',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsPanel(
            diagnostics: diagnostics,
            onSelect: (item) => selected = item,
          ),
        ),
      ),
    );

    expect(find.text('Unknown keyword'), findsOneWidget);
    await tester.tap(find.text('Unknown keyword'));
    await tester.pump();
    expect(selected?.line, 3);
  });

  testWidgets('ProblemsPanel shows empty state', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProblemsPanel(
            diagnostics: [],
            onSelect: _noop,
          ),
        ),
      ),
    );

    expect(find.textContaining('No problems'), findsOneWidget);
    expect(
      find.textContaining('Diagnostics appear here'),
      findsOneWidget,
    );
  });
}

void _noop(DiagnosticInfo _) {}
