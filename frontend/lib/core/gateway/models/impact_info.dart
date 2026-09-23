/// Impact Analysis DTOs — affected tests with confidence + why.
class AnalysisEntityRef {
  const AnalysisEntityRef({
    required this.id,
    required this.kind,
    required this.name,
    required this.filePath,
    this.line = 1,
    this.column = 1,
    this.documentation = '',
    this.detail = '',
  });

  factory AnalysisEntityRef.fromJson(Map<String, dynamic> json) {
    return AnalysisEntityRef(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      name: json['name'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      line: json['line'] as int? ?? 1,
      column: json['column'] as int? ?? 1,
      documentation: json['documentation'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );
  }

  final String id;
  final String kind;
  final String name;
  final String filePath;
  final int line;
  final int column;
  final String documentation;
  final String detail;
}

class ImpactPathEdge {
  const ImpactPathEdge({
    required this.edgeKind,
    required this.confidence,
    this.targetName = '',
    this.sourceFile = '',
    this.sourceLine = 1,
  });

  factory ImpactPathEdge.fromJson(Map<String, dynamic> json) {
    return ImpactPathEdge(
      edgeKind: json['edge_kind'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'low',
      targetName: json['target_name'] as String? ?? '',
      sourceFile: json['source_file'] as String? ?? '',
      sourceLine: json['source_line'] as int? ?? 1,
    );
  }

  final String edgeKind;
  final String confidence;
  final String targetName;
  final String sourceFile;
  final int sourceLine;
}

class ImpactHitInfo {
  const ImpactHitInfo({
    required this.test,
    required this.confidence,
    required this.relation,
    required this.why,
    this.suite,
    this.depth = 0,
    this.path = const [],
  });

  factory ImpactHitInfo.fromJson(Map<String, dynamic> json) {
    final suiteJson = json['suite'];
    return ImpactHitInfo(
      test: AnalysisEntityRef.fromJson(
        json['test'] as Map<String, dynamic>? ?? const {},
      ),
      suite: suiteJson is Map<String, dynamic>
          ? AnalysisEntityRef.fromJson(suiteJson)
          : null,
      confidence: json['confidence'] as String? ?? 'low',
      relation: json['relation'] as String? ?? 'transitive_call',
      why: json['why'] as String? ?? '',
      depth: json['depth'] as int? ?? 0,
      path: (json['path'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ImpactPathEdge.fromJson)
          .toList(),
    );
  }

  final AnalysisEntityRef test;
  final AnalysisEntityRef? suite;
  final String confidence;
  final String relation;
  final String why;
  final int depth;
  final List<ImpactPathEdge> path;

  bool get isCertain => confidence != 'low';
}

class ImpactReportInfo {
  const ImpactReportInfo({
    this.symbol,
    this.seeds = const [],
    this.graphVersion = '',
    this.incrementalRevision = 0,
    this.entityCount = 0,
    this.emptyGraph = false,
    this.items = const [],
    this.uncertain = const [],
  });

  factory ImpactReportInfo.fromJson(Map<String, dynamic> json) {
    final symbolJson = json['symbol'];
    return ImpactReportInfo(
      symbol: symbolJson is Map<String, dynamic>
          ? AnalysisEntityRef.fromJson(symbolJson)
          : null,
      seeds: (json['seeds'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AnalysisEntityRef.fromJson)
          .toList(),
      graphVersion: json['graph_version'] as String? ?? '',
      incrementalRevision: json['incremental_revision'] as int? ?? 0,
      entityCount: json['entity_count'] as int? ?? 0,
      emptyGraph: json['empty_graph'] as bool? ?? false,
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ImpactHitInfo.fromJson)
          .toList(),
      uncertain: (json['uncertain'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ImpactHitInfo.fromJson)
          .toList(),
    );
  }

  final AnalysisEntityRef? symbol;
  final List<AnalysisEntityRef> seeds;
  final String graphVersion;
  final int incrementalRevision;
  final int entityCount;
  final bool emptyGraph;
  final List<ImpactHitInfo> items;
  final List<ImpactHitInfo> uncertain;

  List<ImpactHitInfo> get allHits => [...items, ...uncertain];
}
