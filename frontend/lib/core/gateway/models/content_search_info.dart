class EnclosingSymbolInfo {
  const EnclosingSymbolInfo({
    required this.kind,
    required this.name,
    required this.line,
  });

  factory EnclosingSymbolInfo.fromJson(Map<String, dynamic> json) {
    return EnclosingSymbolInfo(
      kind: json['kind'] as String? ?? '',
      name: json['name'] as String? ?? '',
      line: json['line'] as int? ?? 0,
    );
  }

  final String kind;
  final String name;
  final int line;
}

class ContentMatchInfo {
  const ContentMatchInfo({
    required this.line,
    required this.column,
    required this.text,
    this.before = const [],
    this.after = const [],
    this.enclosing,
  });

  factory ContentMatchInfo.fromJson(Map<String, dynamic> json) {
    final enclosingRaw = json['enclosing'];
    return ContentMatchInfo(
      line: json['line'] as int? ?? 0,
      column: json['column'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      before: (json['before'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      after: (json['after'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      enclosing: enclosingRaw is Map<String, dynamic>
          ? EnclosingSymbolInfo.fromJson(enclosingRaw)
          : null,
    );
  }

  final int line;
  final int column;
  final String text;
  final List<String> before;
  final List<String> after;
  final EnclosingSymbolInfo? enclosing;
}

class ContentFileHitsInfo {
  const ContentFileHitsInfo({
    required this.path,
    required this.matchCount,
    required this.matches,
  });

  factory ContentFileHitsInfo.fromJson(Map<String, dynamic> json) {
    return ContentFileHitsInfo(
      path: json['path'] as String? ?? '',
      matchCount: json['match_count'] as int? ?? 0,
      matches: (json['matches'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ContentMatchInfo.fromJson)
          .toList(),
    );
  }

  final String path;
  final int matchCount;
  final List<ContentMatchInfo> matches;

  String get fileName {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }
}

class ContentSearchResultInfo {
  const ContentSearchResultInfo({
    required this.query,
    required this.truncated,
    required this.filesScanned,
    required this.files,
  });

  factory ContentSearchResultInfo.fromJson(Map<String, dynamic> json) {
    return ContentSearchResultInfo(
      query: json['query'] as String? ?? '',
      truncated: json['truncated'] as bool? ?? false,
      filesScanned: json['files_scanned'] as int? ?? 0,
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ContentFileHitsInfo.fromJson)
          .toList(),
    );
  }

  final String query;
  final bool truncated;
  final int filesScanned;
  final List<ContentFileHitsInfo> files;

  int get totalMatches =>
      files.fold<int>(0, (sum, file) => sum + file.matchCount);
}
