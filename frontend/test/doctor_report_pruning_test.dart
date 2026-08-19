import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/doctor_info.dart';

DoctorFinding _finding({
  required String id,
  String filePath = '',
  List<({String path, String name, int line})> affected = const [],
}) {
  return DoctorFinding(
    id: id,
    inspectionId: 'unused_keyword',
    severity: 'info',
    message: 'Potentially unused keyword',
    confidence: 'medium',
    category: 'maintainability',
    filePath: filePath,
    metadata: affected.isEmpty
        ? const {}
        : {
            'affected_files': [
              for (final item in affected)
                {'path': item.path, 'name': item.name, 'line': item.line},
            ],
          },
  );
}

DoctorReport _report(List<DoctorFinding> findings) {
  return DoctorReport(
    id: 'r1',
    projectId: 'p1',
    profile: 'default',
    createdAt: DateTime.utc(2026, 8, 3),
    summary: DoctorHealthSummary(
      totalFindings: findings.length,
      bySeverity: {'info': findings.length},
      byCategory: {'maintainability': findings.length},
    ),
    findings: findings,
    grouped: const [],
    topRecommendations: const [],
  );
}

void main() {
  test('doctorReportWithoutRemovedPaths drops findings for deleted file', () {
    const deleted = '/tmp/project/resources/dead.resource';
    final report = _report([
      _finding(id: 'f1', filePath: deleted),
      _finding(id: 'f2', filePath: '/tmp/project/resources/live.resource'),
    ]);

    final pruned = doctorReportWithoutRemovedPaths(report, [deleted]);

    expect(pruned.findings.map((f) => f.id), ['f2']);
    expect(pruned.summary.totalFindings, 1);
  });

  test(
    'doctorReportWithoutRemovedPaths drops multi-file findings touching deleted path',
    () {
      const deleted = '/tmp/project/tests/old.robot';
      final report = _report([
        _finding(
          id: 'dup',
          filePath: '/tmp/project/tests/other.robot',
          affected: [
            (path: deleted, name: 'old.robot', line: 1),
            (
              path: '/tmp/project/tests/other.robot',
              name: 'other.robot',
              line: 4,
            ),
          ],
        ),
      ]);

      final pruned = doctorReportWithoutRemovedPaths(report, [deleted]);

      expect(pruned.findings, isEmpty);
      expect(pruned.summary.totalFindings, 0);
    },
  );

  test(
    'doctorReportWithoutRemovedPaths prunes files under deleted directory',
    () {
      const dir = '/tmp/project/resources';
      final report = _report([
        _finding(id: 'f1', filePath: '$dir/dead.resource'),
        _finding(id: 'f2', filePath: '/tmp/project/tests/live.robot'),
      ]);

      final pruned = doctorReportWithoutRemovedPaths(report, [
        dir,
      ], isDirectory: true);

      expect(pruned.findings.map((f) => f.id), ['f2']);
    },
  );
}
