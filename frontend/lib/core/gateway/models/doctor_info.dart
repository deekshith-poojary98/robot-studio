class DoctorProfileInfo {
  const DoctorProfileInfo({
    required this.id,
    required this.title,
    required this.description,
    this.providerIds = const [],
  });

  factory DoctorProfileInfo.fromJson(Map<String, dynamic> json) {
    return DoctorProfileInfo(
      id: json['id'] as String? ?? 'default',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      providerIds: (json['provider_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  final String id;
  final String title;
  final String description;
  final List<String> providerIds;
}

class DoctorProviderInfo {
  const DoctorProviderInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.defaultSeverity,
    this.supportsFix = false,
    this.fixId,
    this.estimatedRisk,
  });

  factory DoctorProviderInfo.fromJson(Map<String, dynamic> json) {
    return DoctorProviderInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'maintainability',
      defaultSeverity: json['default_severity'] as String? ?? 'warning',
      supportsFix: json['supports_fix'] as bool? ?? false,
      fixId: json['fix_id'] as String?,
      estimatedRisk: json['estimated_risk'] as String?,
    );
  }

  final String id;
  final String title;
  final String description;
  final String category;
  final String defaultSeverity;
  final bool supportsFix;
  final String? fixId;
  final String? estimatedRisk;
}

class DoctorProfilesBundle {
  const DoctorProfilesBundle({
    this.profiles = const [],
    this.providers = const [],
  });

  factory DoctorProfilesBundle.fromJson(Map<String, dynamic> json) {
    return DoctorProfilesBundle(
      profiles: (json['profiles'] as List<dynamic>? ?? [])
          .map((e) => DoctorProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      providers: (json['providers'] as List<dynamic>? ?? [])
          .map((e) => DoctorProviderInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<DoctorProfileInfo> profiles;
  final List<DoctorProviderInfo> providers;
}

class DoctorEntityRef {
  const DoctorEntityRef({
    required this.id,
    required this.kind,
    required this.name,
    required this.filePath,
    this.line = 1,
    this.column = 1,
  });

  factory DoctorEntityRef.fromJson(Map<String, dynamic> json) {
    return DoctorEntityRef(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      name: json['name'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
    );
  }

  final String id;
  final String kind;
  final String name;
  final String filePath;
  final int line;
  final int column;
}

class DoctorFinding {
  const DoctorFinding({
    required this.id,
    required this.inspectionId,
    required this.severity,
    required this.message,
    required this.confidence,
    this.category,
    this.rationale = '',
    this.supportsFix = false,
    this.fixId,
    this.estimatedRisk,
    this.entity,
    this.secondaryEntities = const [],
    this.filePath = '',
    this.line = 1,
    this.column = 1,
    this.metadata = const {},
  });

  factory DoctorFinding.fromJson(Map<String, dynamic> json) {
    final entity = json['entity'];
    final secondary = json['secondary_entities'] as List<dynamic>? ?? const [];
    return DoctorFinding(
      id: json['id'] as String? ?? '',
      inspectionId: json['inspection_id'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'high',
      category: json['category'] as String?,
      rationale: json['rationale'] as String? ?? '',
      supportsFix: json['supports_fix'] as bool? ?? false,
      fixId: json['fix_id'] as String?,
      estimatedRisk: json['estimated_risk'] as String?,
      entity: entity is Map<String, dynamic>
          ? DoctorEntityRef.fromJson(entity)
          : null,
      secondaryEntities: secondary
          .whereType<Map<String, dynamic>>()
          .map(DoctorEntityRef.fromJson)
          .toList(),
      filePath: json['file_path'] as String? ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  final String id;
  final String inspectionId;
  final String severity;
  final String message;
  final String confidence;
  final String? category;
  final String rationale;
  final bool supportsFix;
  final String? fixId;
  final String? estimatedRisk;
  final DoctorEntityRef? entity;
  final List<DoctorEntityRef> secondaryEntities;
  final String filePath;
  final int line;
  final int column;
  final Map<String, dynamic> metadata;

  String get locationLabel {
    if (filePath.isEmpty) return '';
    final name = filePath.split('/').last;
    return '$name:$line';
  }

  String? get cyclePath {
    final raw = metadata['cycle_path'];
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return null;
  }

  List<({String path, String name, int line})> get affectedFiles {
    final raw = metadata['affected_files'];
    if (raw is! List) {
      final fallback = <({String path, String name, int line})>[];
      if (entity != null && entity!.filePath.isNotEmpty) {
        fallback.add((
          path: entity!.filePath,
          name: entity!.name,
          line: entity!.line,
        ));
      }
      for (final e in secondaryEntities) {
        if (e.filePath.isEmpty) continue;
        fallback.add((path: e.filePath, name: e.name, line: e.line));
      }
      return fallback;
    }
    final out = <({String path, String name, int line})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = item['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      out.add((
        path: path,
        name: item['name']?.toString() ?? path.split('/').last,
        line: (item['line'] as num?)?.toInt() ?? 1,
      ));
    }
    return out;
  }
}

class DoctorImprovementTrend {
  const DoctorImprovementTrend({
    required this.previousReportId,
    required this.previousTotal,
    required this.previousCritical,
    required this.deltaTotal,
    required this.deltaCritical,
  });

  factory DoctorImprovementTrend.fromJson(Map<String, dynamic> json) {
    return DoctorImprovementTrend(
      previousReportId: json['previous_report_id'] as String? ?? '',
      previousTotal: (json['previous_total'] as num?)?.toInt() ?? 0,
      previousCritical: (json['previous_critical'] as num?)?.toInt() ?? 0,
      deltaTotal: (json['delta_total'] as num?)?.toInt() ?? 0,
      deltaCritical: (json['delta_critical'] as num?)?.toInt() ?? 0,
    );
  }

  final String previousReportId;
  final int previousTotal;
  final int previousCritical;
  final int deltaTotal;
  final int deltaCritical;

  bool get improved => deltaTotal < 0 || deltaCritical < 0;
}

class DoctorHealthSummary {
  const DoctorHealthSummary({
    this.totalFindings = 0,
    this.bySeverity = const {},
    this.byCategory = const {},
    this.criticalIssues = 0,
    this.improvementTrend,
  });

  factory DoctorHealthSummary.fromJson(Map<String, dynamic> json) {
    final trend = json['improvement_trend'];
    return DoctorHealthSummary(
      totalFindings: (json['total_findings'] as num?)?.toInt() ?? 0,
      bySeverity: Map<String, int>.from(
        (json['by_severity'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        ),
      ),
      byCategory: Map<String, int>.from(
        (json['by_category'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        ),
      ),
      criticalIssues: (json['critical_issues'] as num?)?.toInt() ?? 0,
      improvementTrend: trend is Map<String, dynamic>
          ? DoctorImprovementTrend.fromJson(trend)
          : null,
    );
  }

  final int totalFindings;
  final Map<String, int> bySeverity;
  final Map<String, int> byCategory;
  final int criticalIssues;
  final DoctorImprovementTrend? improvementTrend;
}

class DoctorRecommendation {
  const DoctorRecommendation({
    required this.rank,
    required this.findingId,
    required this.reason,
    required this.finding,
  });

  factory DoctorRecommendation.fromJson(Map<String, dynamic> json) {
    return DoctorRecommendation(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      findingId: json['finding_id'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      finding: DoctorFinding.fromJson(
        json['finding'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  final int rank;
  final String findingId;
  final String reason;
  final DoctorFinding finding;
}

class DoctorCategoryGroup {
  const DoctorCategoryGroup({required this.category, this.findings = const []});

  factory DoctorCategoryGroup.fromJson(Map<String, dynamic> json) {
    return DoctorCategoryGroup(
      category: json['category'] as String? ?? '',
      findings: (json['findings'] as List<dynamic>? ?? [])
          .map((e) => DoctorFinding.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String category;
  final List<DoctorFinding> findings;
}

class DoctorExecutionSnapshot {
  const DoctorExecutionSnapshot({
    required this.projectId,
    this.linkedRuns = 0,
    this.entitiesWithStats = 0,
    this.executionEdges = 0,
  });

  factory DoctorExecutionSnapshot.fromJson(Map<String, dynamic> json) {
    return DoctorExecutionSnapshot(
      projectId: json['project_id'] as String? ?? '',
      linkedRuns: (json['linked_runs'] as num?)?.toInt() ?? 0,
      entitiesWithStats: (json['entities_with_stats'] as num?)?.toInt() ?? 0,
      executionEdges: (json['execution_edges'] as num?)?.toInt() ?? 0,
    );
  }

  final String projectId;
  final int linkedRuns;
  final int entitiesWithStats;
  final int executionEdges;
}

/// Drops findings that reference paths removed from the workspace.
///
/// Used when files are deleted without re-running Doctor — the last report
/// would otherwise keep showing errors for paths that no longer exist.
DoctorReport doctorReportWithoutRemovedPaths(
  DoctorReport report,
  Iterable<String> removedPaths, {
  bool Function(String, String)? pathsEqual,
  bool isDirectory = false,
}) {
  final removed = removedPaths.where((p) => p.trim().isNotEmpty).toList();
  if (removed.isEmpty || report.findings.isEmpty) return report;

  bool eq(String a, String b) =>
      pathsEqual?.call(a, b) ??
      a.replaceAll('\\', '/') == b.replaceAll('\\', '/');

  bool isUnderDirectory(String path, String dir) {
    final normPath = path.replaceAll('\\', '/');
    final normDir = dir.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    if (eq(normPath, normDir)) return true;
    return normPath.startsWith('$normDir/');
  }

  bool referencesRemoved(String path) {
    if (path.isEmpty) return false;
    for (final target in removed) {
      if (eq(path, target)) return true;
      if (isDirectory && isUnderDirectory(path, target)) return true;
    }
    return false;
  }

  bool shouldDrop(DoctorFinding finding) {
    if (referencesRemoved(finding.filePath)) return true;
    final entity = finding.entity;
    if (entity != null && referencesRemoved(entity.filePath)) return true;
    for (final secondary in finding.secondaryEntities) {
      if (referencesRemoved(secondary.filePath)) return true;
    }
    for (final affected in finding.affectedFiles) {
      if (referencesRemoved(affected.path)) return true;
    }
    return false;
  }

  final kept = report.findings.where((f) => !shouldDrop(f)).toList();
  if (kept.length == report.findings.length) return report;

  final bySeverity = <String, int>{};
  final byCategory = <String, int>{};
  var critical = 0;
  for (final finding in kept) {
    bySeverity[finding.severity] = (bySeverity[finding.severity] ?? 0) + 1;
    final category = finding.category ?? 'maintainability';
    byCategory[category] = (byCategory[category] ?? 0) + 1;
    if (finding.severity == 'error') critical++;
  }

  final keptIds = kept.map((f) => f.id).toSet();
  final groupedMap = <String, List<DoctorFinding>>{};
  for (final finding in kept) {
    final key = finding.category ?? 'maintainability';
    groupedMap.putIfAbsent(key, () => []).add(finding);
  }

  final recommendations = <DoctorRecommendation>[];
  var rank = 1;
  for (final rec in report.topRecommendations) {
    if (!keptIds.contains(rec.findingId)) continue;
    recommendations.add(
      DoctorRecommendation(
        rank: rank,
        findingId: rec.findingId,
        reason: rec.reason,
        finding: rec.finding,
      ),
    );
    rank++;
    if (rank > 5) break;
  }

  return DoctorReport(
    id: report.id,
    projectId: report.projectId,
    profile: report.profile,
    createdAt: report.createdAt,
    graphVersion: report.graphVersion,
    incrementalRevision: report.incrementalRevision,
    providersRun: report.providersRun,
    summary: DoctorHealthSummary(
      totalFindings: kept.length,
      bySeverity: bySeverity,
      byCategory: byCategory,
      criticalIssues: critical,
      improvementTrend: report.summary.improvementTrend,
    ),
    findings: kept,
    grouped: [
      for (final entry in groupedMap.entries)
        DoctorCategoryGroup(category: entry.key, findings: entry.value),
    ],
    topRecommendations: recommendations,
    executionSnapshot: report.executionSnapshot,
  );
}

class DoctorReport {
  const DoctorReport({
    required this.id,
    required this.projectId,
    required this.profile,
    required this.createdAt,
    required this.summary,
    this.graphVersion = '',
    this.incrementalRevision = 0,
    this.providersRun = const [],
    this.findings = const [],
    this.grouped = const [],
    this.topRecommendations = const [],
    this.executionSnapshot,
  });

  factory DoctorReport.fromJson(Map<String, dynamic> json) {
    final snap = json['execution_snapshot'];
    return DoctorReport(
      id: json['id'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      profile: json['profile'] as String? ?? 'default',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      graphVersion: json['graph_version'] as String? ?? '',
      incrementalRevision: (json['incremental_revision'] as num?)?.toInt() ?? 0,
      providersRun: (json['providers_run'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      summary: DoctorHealthSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? {},
      ),
      findings: (json['findings'] as List<dynamic>? ?? [])
          .map((e) => DoctorFinding.fromJson(e as Map<String, dynamic>))
          .toList(),
      grouped: (json['grouped'] as List<dynamic>? ?? [])
          .map((e) => DoctorCategoryGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
      topRecommendations: (json['top_recommendations'] as List<dynamic>? ?? [])
          .map((e) => DoctorRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      executionSnapshot: snap is Map<String, dynamic>
          ? DoctorExecutionSnapshot.fromJson(snap)
          : null,
    );
  }

  final String id;
  final String projectId;
  final String profile;
  final DateTime createdAt;
  final String graphVersion;
  final int incrementalRevision;
  final List<String> providersRun;
  final DoctorHealthSummary summary;
  final List<DoctorFinding> findings;
  final List<DoctorCategoryGroup> grouped;
  final List<DoctorRecommendation> topRecommendations;
  final DoctorExecutionSnapshot? executionSnapshot;
}

class DoctorReportSummary {
  const DoctorReportSummary({
    required this.id,
    required this.projectId,
    required this.profile,
    required this.createdAt,
    this.graphVersion = '',
    this.totalFindings = 0,
    this.criticalIssues = 0,
    this.providersRun = const [],
  });

  factory DoctorReportSummary.fromJson(Map<String, dynamic> json) {
    return DoctorReportSummary(
      id: json['id'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      profile: json['profile'] as String? ?? 'default',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      graphVersion: json['graph_version'] as String? ?? '',
      totalFindings: (json['total_findings'] as num?)?.toInt() ?? 0,
      criticalIssues: (json['critical_issues'] as num?)?.toInt() ?? 0,
      providersRun: (json['providers_run'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  final String id;
  final String projectId;
  final String profile;
  final DateTime createdAt;
  final String graphVersion;
  final int totalFindings;
  final int criticalIssues;
  final List<String> providersRun;
}
