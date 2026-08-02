enum SymbolKind {
  keyword,
  variable,
  library,
  resource,
  testSuite,
  testCase,
  setting,
  tag,
  documentation,
  file;

  static SymbolKind fromApi(String value) {
    return switch (value) {
      'keyword' => SymbolKind.keyword,
      'variable' => SymbolKind.variable,
      'library' => SymbolKind.library,
      'resource' => SymbolKind.resource,
      'test_suite' => SymbolKind.testSuite,
      'test_case' => SymbolKind.testCase,
      'setting' => SymbolKind.setting,
      'tag' => SymbolKind.tag,
      'documentation' => SymbolKind.documentation,
      'file' => SymbolKind.file,
      _ => SymbolKind.keyword,
    };
  }

  String get apiValue => switch (this) {
        SymbolKind.keyword => 'keyword',
        SymbolKind.variable => 'variable',
        SymbolKind.library => 'library',
        SymbolKind.resource => 'resource',
        SymbolKind.testSuite => 'test_suite',
        SymbolKind.testCase => 'test_case',
        SymbolKind.setting => 'setting',
        SymbolKind.tag => 'tag',
        SymbolKind.documentation => 'documentation',
        SymbolKind.file => 'file',
      };

  String get label => switch (this) {
        SymbolKind.keyword => 'Keyword',
        SymbolKind.variable => 'Variable',
        SymbolKind.library => 'Library',
        SymbolKind.resource => 'Resource',
        SymbolKind.testSuite => 'Test Suite',
        SymbolKind.testCase => 'Test Case',
        SymbolKind.setting => 'Setting',
        SymbolKind.tag => 'Tag',
        SymbolKind.documentation => 'Documentation',
        SymbolKind.file => 'File',
      };
}

class IndexedSymbolInfo {
  const IndexedSymbolInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.filePath,
    required this.line,
    this.projectId,
    this.workspaceId,
    this.documentation = '',
    this.detail = '',
    this.lastModified,
    this.definitions = const [],
  });

  factory IndexedSymbolInfo.fromJson(Map<String, dynamic> json) {
    final nested = json['definitions'];
    final alternatives = <IndexedSymbolInfo>[];
    if (nested is List) {
      for (final item in nested) {
        if (item is Map<String, dynamic>) {
          alternatives.add(
            IndexedSymbolInfo.fromJson({
              ...item,
              // Avoid recursive nesting.
              'definitions': null,
            }),
          );
        }
      }
    }
    return IndexedSymbolInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: SymbolKind.fromApi(json['kind'] as String),
      filePath: json['file_path'] as String,
      line: (json['line'] as num?)?.toInt() ?? 1,
      projectId: json['project_id'] as String?,
      workspaceId: json['workspace_id'] as String?,
      documentation: json['documentation'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      lastModified: (json['last_modified'] as num?)?.toDouble(),
      definitions: alternatives,
    );
  }

  final String id;
  final String name;
  final SymbolKind kind;
  final String filePath;
  final int line;
  final String? projectId;
  final String? workspaceId;
  final String documentation;
  final String detail;
  final double? lastModified;
  final List<IndexedSymbolInfo> definitions;

  String get locationLabel => '$filePath:$line';
}

class SymbolReferenceInfo {
  const SymbolReferenceInfo({
    required this.name,
    required this.filePath,
    required this.line,
    this.symbolId = '',
    this.projectId,
    this.context = '',
  });

  factory SymbolReferenceInfo.fromJson(Map<String, dynamic> json) {
    return SymbolReferenceInfo(
      symbolId: json['symbol_id'] as String? ?? '',
      name: json['name'] as String,
      filePath: json['file_path'] as String,
      line: (json['line'] as num?)?.toInt() ?? 1,
      projectId: json['project_id'] as String?,
      context: json['context'] as String? ?? '',
    );
  }

  final String symbolId;
  final String name;
  final String filePath;
  final int line;
  final String? projectId;
  final String context;
}

class IndexStatusInfo {
  const IndexStatusInfo({
    required this.state,
    this.filesIndexed = 0,
    this.keywordsIndexed = 0,
    this.librariesIndexed = 0,
    this.variablesIndexed = 0,
    this.symbolsIndexed = 0,
    this.lastIndexedAt,
    this.message = '',
    this.errors = const [],
  });

  factory IndexStatusInfo.fromJson(Map<String, dynamic> json) {
    return IndexStatusInfo(
      state: json['state'] as String? ?? 'idle',
      filesIndexed: (json['files_indexed'] as num?)?.toInt() ?? 0,
      keywordsIndexed: (json['keywords_indexed'] as num?)?.toInt() ?? 0,
      librariesIndexed: (json['libraries_indexed'] as num?)?.toInt() ?? 0,
      variablesIndexed: (json['variables_indexed'] as num?)?.toInt() ?? 0,
      symbolsIndexed: (json['symbols_indexed'] as num?)?.toInt() ?? 0,
      lastIndexedAt: json['last_indexed_at'] == null
          ? null
          : DateTime.parse(json['last_indexed_at'] as String),
      message: json['message'] as String? ?? '',
      errors: (json['errors'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  final String state;
  final int filesIndexed;
  final int keywordsIndexed;
  final int librariesIndexed;
  final int variablesIndexed;
  final int symbolsIndexed;
  final DateTime? lastIndexedAt;
  final String message;
  final List<String> errors;

  String get lastIndexedLabel {
    final value = lastIndexedAt;
    if (value == null) return 'Never';
    final local = value.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class HoverInfo {
  const HoverInfo({
    required this.name,
    required this.kind,
    required this.filePath,
    required this.line,
    this.documentation = '',
    this.detail = '',
    this.id = '',
  });

  factory HoverInfo.fromJson(Map<String, dynamic> json) {
    return HoverInfo(
      name: json['name'] as String,
      kind: SymbolKind.fromApi(json['kind'] as String),
      filePath: json['file_path'] as String,
      line: (json['line'] as num?)?.toInt() ?? 1,
      documentation: json['documentation'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );
  }

  final String name;
  final SymbolKind kind;
  final String filePath;
  final int line;
  final String documentation;
  final String detail;
  final String id;
}
