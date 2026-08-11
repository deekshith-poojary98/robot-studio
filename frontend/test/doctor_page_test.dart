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
          title: 'Structural',
          description: 'Structural project health',
          providerIds: [
            'circular_dependency',
            'duplicate_keyword',
            'unused_keyword',
            'unused_resource',
          ],
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
          inspectionId: 'circular_dependency',
          severity: 'error',
          message:
              'Circular Resource import: login.resource → common.resource → login.resource',
          confidence: 'high',
          category: 'dependencies',
          rationale:
              'These resources or suites import each other in a cycle. '
              'Break the cycle by moving shared keywords into a third resource.',
          filePath: 'resources/login.resource',
          line: 12,
          metadata: {
            'cycle_path': 'login.resource → common.resource → login.resource',
            'affected_files': [
              {
                'path': 'resources/login.resource',
                'name': 'login.resource',
                'line': 12,
              },
              {
                'path': 'resources/common.resource',
                'name': 'common.resource',
                'line': 4,
              },
            ],
          },
        ),
      ],
      grouped: const [
        DoctorCategoryGroup(
          category: 'dependencies',
          findings: [
            DoctorFinding(
              id: 'f1',
              inspectionId: 'circular_dependency',
              severity: 'error',
              message:
                  'Circular Resource import: login.resource → common.resource → login.resource',
              confidence: 'high',
              category: 'dependencies',
              rationale:
                  'These resources or suites import each other in a cycle.',
              filePath: 'resources/login.resource',
              line: 12,
            ),
          ],
        ),
      ],
      topRecommendations: const [
        DoctorRecommendation(
          rank: 1,
          findingId: 'f1',
          reason:
              'Break this import cycle before it causes load-order failures.',
          finding: DoctorFinding(
            id: 'f1',
            inspectionId: 'circular_dependency',
            severity: 'error',
            message:
                'Circular Resource import: login.resource → common.resource → login.resource',
            confidence: 'high',
            category: 'dependencies',
            rationale:
                'These resources or suites import each other in a cycle.',
            filePath: 'resources/login.resource',
            line: 12,
          ),
        ),
      ],
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
  testWidgets('Doctor page shows structural finding details', (tester) async {
    String? jumped;
    int? jumpedLine;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DoctorPage(
            gateway: _DoctorGateway(),
            onJumpToSource: (path, {line, column}) {
              jumped = path;
              jumpedLine = line;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Robot Doctor'), findsOneWidget);
    expect(
      find.textContaining('Structural problems across the project'),
      findsOneWidget,
    );
    expect(find.text('Scan project'), findsOneWidget);
    expect(find.text('Fix first'), findsOneWidget);
    expect(find.textContaining('Circular Resource import'), findsWidgets);
    expect(find.textContaining('Circular imports'), findsWidgets);
    expect(find.text('ERROR'), findsWidgets);
    expect(find.text('Quick'), findsNothing);
    expect(find.text('Full'), findsNothing);
    expect(find.text('BLOCKERS'), findsOneWidget);

    // Expand via the findings list (not Fix first), then open source.
    final findingRows = find.textContaining('Circular Resource import');
    await tester.tap(findingRows.at(findingRows.evaluate().length - 1));
    await tester.pumpAndSettle();

    expect(find.text('Why this matters'), findsOneWidget);
    expect(find.text('Import cycle'), findsOneWidget);
    expect(find.text('Affected files'), findsOneWidget);
    expect(find.textContaining('login.resource:12'), findsWidgets);
    expect(find.byKey(const Key('doctor-open-source')), findsOneWidget);
    expect(find.text('Quick Fix'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('doctor-open-source')));
    await tester.tap(find.byKey(const Key('doctor-open-source')));
    await tester.pumpAndSettle();
    expect(jumped, 'resources/login.resource');
    expect(jumpedLine, 12);
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
  });
}
