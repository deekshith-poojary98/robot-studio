import 'language_info.dart';

/// REST mirror of backend LibraryMetadata (summary or detail).
class LibraryInfo {
  const LibraryInfo({
    required this.name,
    this.version = '',
    this.documentation = '',
    this.sourceType = '',
    this.sourcePath = '',
    this.builtin = false,
    this.keywordCount = 0,
    this.lastUpdated,
    this.keywords = const [],
  });

  factory LibraryInfo.fromJson(Map<String, dynamic> json) {
    return LibraryInfo(
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? '',
      sourcePath: json['source_path'] as String? ?? '',
      builtin: json['builtin'] as bool? ?? false,
      keywordCount: (json['keyword_count'] as num?)?.toInt() ?? 0,
      lastUpdated: json['last_updated'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? [])
          .map((item) => LibraryKeywordInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String name;
  final String version;
  final String documentation;
  final String sourceType;
  final String sourcePath;
  final bool builtin;
  final int keywordCount;
  final String? lastUpdated;
  final List<LibraryKeywordInfo> keywords;
}

/// REST mirror of KeywordMetadata — rendered directly in the detail pane.
class LibraryKeywordInfo {
  const LibraryKeywordInfo({
    required this.name,
    this.qualifiedName = '',
    this.sourceType = '',
    this.libraryName = '',
    this.documentation = '',
    this.parameters = const [],
    this.sourcePath = '',
    this.sourceLine,
    this.deprecated = false,
    this.tags = const [],
    this.detail = '',
  });

  factory LibraryKeywordInfo.fromJson(Map<String, dynamic> json) {
    return LibraryKeywordInfo(
      name: json['name'] as String? ?? '',
      qualifiedName: json['qualified_name'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? '',
      libraryName: json['library_name'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      parameters: (json['parameters'] as List<dynamic>? ?? [])
          .map((item) => SignatureParameterInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      sourcePath: json['source_path'] as String? ?? '',
      sourceLine: (json['source_line'] as num?)?.toInt(),
      deprecated: json['deprecated'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>? ?? []).map((t) => '$t').toList(),
      detail: json['detail'] as String? ?? '',
    );
  }

  final String name;
  final String qualifiedName;
  final String sourceType;
  final String libraryName;
  final String documentation;
  final List<SignatureParameterInfo> parameters;
  final String sourcePath;
  final int? sourceLine;
  final bool deprecated;
  final List<String> tags;
  final String detail;

  bool get canJumpToSource => sourcePath.isNotEmpty;
}
