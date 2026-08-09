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
                  counts: {'keyword': 2, 'test_case': 1},
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
            onOpenReports: () {},
          ),
        ),
      ),
    );

    expect(find.text('Composition'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('70%'), findsWidgets);
    expect(find.text('demo.robot'), findsWidgets);
    expect(find.text('View in Reports'), findsOneWidget);
    expect(find.text('Run health'), findsOneWidget);
    expect(find.text('Pass rate'), findsOneWidget);
    expect(find.text('DURATION TREND'), findsOneWidget);
    expect(find.text('LAST RUN'), findsOneWidget);
  });
}
