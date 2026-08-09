import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/doctor/doctor_page.dart';

class _DoctorGateway implements TransportGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<DoctorProfilesBundle> getDoctorProfiles() async {
    return const DoctorProfilesBundle(
      profiles: [
        DoctorProfileInfo(
          id: 'default',
          title: 'Default',
          description: 'Static inspections',
          providerIds: ['missing_import'],
        ),
        DoctorProfileInfo(
          id: 'quick',
          title: 'Quick',
          description: 'Fast',
          providerIds: ['missing_import'],
        ),
      ],
    );
  }

  @override
  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  }) async {
    return DoctorReport(
      id: 'r1',
      projectId: 'p1',
      profile: profile,
      createdAt: DateTime.utc(2026, 8, 3),
      graphVersion: 'abc12345',
      summary: const DoctorHealthSummary(
        totalFindings: 1,
        bySeverity: {'error': 1},
        byCategory: {'dependencies': 1},
        criticalIssues: 1,
      ),
      findings: const [
        DoctorFinding(
          id: 'f1',
          inspectionId: 'missing_import',
          severity: 'error',
          message: "Unresolved import 'missing.resource'",
          confidence: 'low',
          category: 'dependencies',
          rationale: 'Import path could not be resolved on disk.',
          supportsFix: true,
          fixId: 'fix_missing_import',
          filePath: 'tests/login.robot',
          line: 3,
        ),
      ],
      grouped: const [
        DoctorCategoryGroup(
          category: 'dependencies',
          findings: [
            DoctorFinding(
              id: 'f1',
              inspectionId: 'missing_import',
              severity: 'error',
              message: "Unresolved import 'missing.resource'",
              confidence: 'low',
              category: 'dependencies',
              rationale: 'Import path could not be resolved on disk.',
              supportsFix: true,
              filePath: 'tests/login.robot',
              line: 3,
            ),
          ],
        ),
      ],
      topRecommendations: const [
        DoctorRecommendation(
          rank: 1,
          findingId: 'f1',
          reason:
              'Critical correctness / dependency issue — fix before shipping.',
          finding: DoctorFinding(
            id: 'f1',
            inspectionId: 'missing_import',
            severity: 'error',
            message: "Unresolved import 'missing.resource'",
            confidence: 'low',
            category: 'dependencies',
            rationale: 'Import path could not be resolved on disk.',
            supportsFix: true,
            filePath: 'tests/login.robot',
            line: 3,
          ),
        ),
      ],
      executionSnapshot: const DoctorExecutionSnapshot(
        projectId: 'p1',
        linkedRuns: 4,
      ),
    );
  }
}

class _DoctorGatewayWithTrend extends _DoctorGateway {
  @override
  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  }) async {
    final base = await super.runDoctor(profile: profile);
    return DoctorReport(
      id: base.id,
      projectId: base.projectId,
      profile: base.profile,
      createdAt: base.createdAt,
      graphVersion: base.graphVersion,
      summary: DoctorHealthSummary(
        totalFindings: base.summary.totalFindings,
        bySeverity: base.summary.bySeverity,
        byCategory: base.summary.byCategory,
        criticalIssues: base.summary.criticalIssues,
        improvementTrend: const DoctorImprovementTrend(
          previousReportId: 'prev',
          previousTotal: 3,
          previousCritical: 2,
          deltaTotal: -2,
          deltaCritical: -1,
        ),
      ),
      findings: base.findings,
      grouped: base.grouped,
      topRecommendations: base.topRecommendations,
      executionSnapshot: base.executionSnapshot,
    );
  }
}

void main() {
  testWidgets('Doctor page shows health summary and findings', (tester) async {
    String? jumped;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DoctorPage(
            gateway: _DoctorGateway(),
            onJumpToSource: (path, {line, column}) {
              jumped = path;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Robot Doctor'), findsOneWidget);
    expect(find.textContaining('Find project problems ranked'), findsOneWidget);
    expect(find.text('Fix first'), findsOneWidget);
    expect(find.textContaining('Unresolved import'), findsWidgets);
    expect(find.textContaining('Imports & libraries'), findsWidgets);
    expect(find.text('ERROR'), findsWidgets);
    expect(find.text('GRAPH'), findsNothing);
    expect(find.text('LINKED RUNS'), findsNothing);
    expect(find.text('FINDINGS'), findsOneWidget);
    expect(
      find.textContaining('Includes lessons from 4 past test runs'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Unresolved import').first);
    await tester.pumpAndSettle();

    expect(find.text('Why is this reported?'), findsOneWidget);
    expect(find.textContaining('could not be resolved'), findsOneWidget);
    expect(find.textContaining('Confidence: low'), findsOneWidget);
    expect(find.text('Jump to source'), findsOneWidget);
    expect(find.text('Quick Fix'), findsNothing);

    await tester.tap(find.text('Jump to source'));
    await tester.pumpAndSettle();
    expect(jumped, 'tests/login.robot');
  });

  testWidgets('Doctor summary uses plain-language trend', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: DoctorPage(gateway: _DoctorGatewayWithTrend())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SINCE LAST SCAN'), findsOneWidget);
    expect(find.text('2 fewer'), findsOneWidget);
    expect(find.text('GRAPH'), findsNothing);
  });
}
