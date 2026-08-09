import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/insights_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/insights/insights_page.dart';

void main() {
  testWidgets('Insights empty composition and runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InsightsPage(
            insights: const InsightsInfo(),
            isLoading: false,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.textContaining('No indexed symbols yet'), findsOneWidget);
    expect(find.textContaining('No runs yet'), findsOneWidget);
  });

  testWidgets('Insights shows composition and run metrics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InsightsPage(
            insights: InsightsInfo(
              composition: const {'keyword': 12, 'test_case': 4, 'variable': 3},
              compositionFiles: const [
                InsightsFileComposition(
                  filePath: '/proj/tests/demo.robot',
                  counts: {'keyword': 2, 'test_case': 3},
                ),
                InsightsFileComposition(
                  filePath: '/proj/resources/common.resource',
                  counts: {'keyword': 5, 'test_case': 0},
                ),
              ],
              runs: const InsightsRunTotals(
                total: 10,
                passed: 7,
                failed: 2,
                cancelled: 1,
                passRate: 70,
                averageDurationMs: 1500,
              ),
              recentRuns: [
                InsightsRecentRun(
                  id: '1',
                  suite: '/proj/tests/demo.robot',
                  startedAt: DateTime.utc(2026, 8, 9, 12),
                  durationMs: 1200,
                  passed: 4,
                  failed: 0,
                  outcome: 'PASS',
                ),
                InsightsRecentRun(
                  id: '3',
                  suite: '/proj/tests/demo.robot',
                  startedAt: DateTime.utc(2026, 8, 9, 11, 30),
                  durationMs: 1800,
                  passed: 2,
                  failed: 1,
                  outcome: 'FAIL',
                ),
                InsightsRecentRun(
                  id: '2',
                  suite: '/proj/tests/demo.robot',
                  startedAt: DateTime.utc(2026, 8, 9, 11),
                  durationMs: 2400,
                  passed: 3,
                  failed: 1,
                  outcome: 'FAIL',
                ),
              ],
              runFiles: const [
                InsightsFileRuns(
                  filePath: '/proj/tests/demo.robot',
                  runs: 5,
                  passed: 3,
                  failed: 2,
                  lastOutcome: 'FAIL',
                ),
              ],
            ),
            isLoading: false,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('Composition'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('70%'), findsWidgets);
    expect(find.text('demo.robot'), findsWidgets);
    expect(find.text('View in Reports'), findsNothing);
    expect(find.text('Run health'), findsOneWidget);
    expect(find.text('Pass rate'), findsNothing);
    expect(find.text('Failed'), findsNothing);
    expect(find.text('Avg duration'), findsNothing);
    expect(find.textContaining('streak'), findsWidgets);
    expect(find.text('Flaky files'), findsOneWidget);
    expect(find.text('Interrupted'), findsOneWidget);
    expect(find.text('PASS RATE TREND'), findsOneWidget);
    expect(find.text('DURATION TREND'), findsOneWidget);
    expect(find.text('FAILURE MIX BY SUITE'), findsOneWidget);
    expect(find.text('LAST RUN'), findsOneWidget);
    expect(find.textContaining('4 passed'), findsOneWidget);
    expect(find.textContaining('0 failed'), findsOneWidget);
    expect(find.textContaining('2 failed · 5 runs'), findsOneWidget);
    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('DENSEST FILES'), findsOneWidget);
    expect(find.text('COMPOSITION MIX'), findsOneWidget);
    expect(find.text('FILE TYPES'), findsOneWidget);
    expect(find.text('TEST-HEAVY FILES'), findsOneWidget);
    expect(find.textContaining('3 tests'), findsOneWidget);
    expect(find.text('.robot'), findsOneWidget);
    expect(find.text('.resource'), findsOneWidget);
    // Zero kinds stay visible (muted), not hidden.
    expect(find.text('Libraries'), findsOneWidget);
    expect(find.text('Resources'), findsWidgets);
  });

  testWidgets('Composition large counts stay single-line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: InsightsPage(
              insights: const InsightsInfo(
                composition: {
                  'keyword': 2,
                  'test_case': 1000000,
                  'test_suite': 10000,
                  'file': 10001,
                },
              ),
              isLoading: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('1,000,000'), findsWidgets);
    expect(find.text('10,000'), findsOneWidget);
    expect(find.textContaining('1,000,002 indexed'), findsOneWidget);
    // Must not appear as a wrapped raw digit break (e.g. 1000\n000).
    expect(find.text('1000000'), findsNothing);
  });
}
