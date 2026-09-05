import 'index_info.dart';

enum DiagnosticSeverity {
  error,
  warning,
  information;

  static DiagnosticSeverity fromApi(String value) {
    return switch (value) {
      'error' => DiagnosticSeverity.error,
      'warning' => DiagnosticSeverity.warning,
      'information' => DiagnosticSeverity.information,
      _ => DiagnosticSeverity.error,
    };
  }

  String get apiValue => switch (this) {
    DiagnosticSeverity.error => 'error',
    DiagnosticSeverity.warning => 'warning',
    DiagnosticSeverity.information => 'information',
  };
}

class CompletionItemInfo {
  const CompletionItemInfo({
    required this.label,
    required this.kind,
    this.detail = '',
    this.documentation = '',
    this.insertText = '',
    this.provider = '',
  });

  factory CompletionItemInfo.fromJson(Map<String, dynamic> json) {
    return CompletionItemInfo(
      label: json['label'] as String,
      kind: json['kind'] as String? ?? 'keyword',
      detail: json['detail'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      insertText: json['insert_text'] as String? ?? json['label'] as String,
      provider: json['provider'] as String? ?? '',
    );
  }

  final String label;
  final String kind;
  final String detail;
  final String documentation;
  final String insertText;
  final String provider;
}

class QuickFixHint {
  const QuickFixHint({
    required this.kind,
    required this.title,
    this.package,
    this.library,
  });

  factory QuickFixHint.fromJson(Map<String, dynamic> json) {
    return QuickFixHint(
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? 'Fix',
      package: json['package'] as String?,
      library: json['library'] as String?,
    );
  }

  /// `install_package` or `insert_library`.
  final String kind;
  final String title;
  final String? package;
  final String? library;

  bool get isInstallPackage =>
      kind == 'install_package' && (package ?? '').isNotEmpty;

  bool get isInsertLibrary =>
      kind == 'insert_library' && (library ?? '').isNotEmpty;
}

class DiagnosticInfo {
  const DiagnosticInfo({
    required this.severity,
    required this.filePath,
    required this.line,
    required this.column,
    required this.message,
    this.source = 'robot',
    this.code,
    this.inspectionId,
    this.quickFix,
  });

  factory DiagnosticInfo.fromJson(Map<String, dynamic> json) {
    final rawFix = json['quick_fix'];
    return DiagnosticInfo(
      severity: DiagnosticSeverity.fromApi(
        json['severity'] as String? ?? 'error',
      ),
      filePath: json['file_path'] as String? ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? 'robot',
      code: json['code'] as String?,
      inspectionId: json['inspection_id'] as String?,
      quickFix: rawFix is Map<String, dynamic>
          ? QuickFixHint.fromJson(rawFix)
          : null,
    );
  }

  final DiagnosticSeverity severity;
  final String filePath;
  final int line;
  final int column;
  final String message;
  final String source;
  final String? code;
  final String? inspectionId;
  final QuickFixHint? quickFix;

  String get fileName {
    final normalized = filePath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty || parts.last.isEmpty ? filePath : parts.last;
  }

  String get locationLabel => '$fileName:$line:$column';

  String get sourceLabel {
    final bits = <String>[source];
    if (code != null && code!.isNotEmpty) bits.add(code!);
    return bits.join(' · ');
  }
}

class SignatureParameterInfo {
  const SignatureParameterInfo({
    required this.label,
    this.name = '',
    this.documentation = '',
    this.defaultValue,
    this.required = false,
    this.kind = '',
  });

  factory SignatureParameterInfo.fromJson(Map<String, dynamic> json) {
    return SignatureParameterInfo(
      label: json['label'] as String? ?? '',
      name: json['name'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      defaultValue: json['default'] as String?,
      required: json['required'] as bool? ?? false,
      kind: json['kind'] as String? ?? '',
    );
  }

  final String label;
  final String name;
  final String documentation;
  final String? defaultValue;
  final bool required;
  final String kind;

  String get displayLabel {
    if (label.isNotEmpty) {
      return _hasRobotVariableWrapper(label)
          ? pythonStyleParameterLabel(label)
          : label;
    }
    if (name.isEmpty) return '';
    final bare = bareParameterName(name);
    if (defaultValue != null) return '$bare=$defaultValue';
    return bare;
  }

  /// RF ``${locator}`` / ``@{items}`` → ``locator`` / ``items``.
  static String bareParameterName(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    final eq = text.indexOf('=');
    if (eq > 0) text = text.substring(0, eq).trim();
    final colon = text.indexOf(':');
    if (colon > 0) text = text.substring(0, colon).trim();
    return _unwrapRobotVariable(text);
  }

  static bool _hasRobotVariableWrapper(String text) {
    return text.contains(r'${') ||
        text.contains('@{') ||
        text.contains('&{') ||
        text.contains('%{');
  }

  static String pythonStyleParameterLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (!_hasRobotVariableWrapper(trimmed)) return trimmed;
    var head = trimmed;
    String? defaultPart;
    final eq = trimmed.indexOf('=');
    if (eq > 0) {
      head = trimmed.substring(0, eq).trim();
      defaultPart = trimmed.substring(eq + 1);
    }
    var namePart = head;
    String? typePart;
    final colon = head.indexOf(':');
    if (colon > 0) {
      namePart = head.substring(0, colon).trim();
      typePart = head.substring(colon + 1).trim();
    }
    final name = _unwrapRobotVariable(namePart);
    final out = StringBuffer(name);
    if (typePart != null && typePart.isNotEmpty) {
      out.write(': $typePart');
    }
    if (defaultPart != null) {
      out.write('=$defaultPart');
    }
    return out.toString();
  }

  static String _unwrapRobotVariable(String text) {
    if (text.length >= 4 &&
        r'$@&%'.contains(text[0]) &&
        text[1] == '{' &&
        text.endsWith('}')) {
      final inner = text.substring(2, text.length - 1).trim();
      if (inner.isNotEmpty) return inner;
    }
    return text;
  }
}

/// One file's full new contents after a rename.
class RenameFileEditInfo {
  const RenameFileEditInfo({required this.filePath, required this.content});

  factory RenameFileEditInfo.fromJson(Map<String, dynamic> json) {
    return RenameFileEditInfo(
      filePath: json['file_path'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  final String filePath;
  final String content;
}

/// Result of a rename request. [error] is non-empty when the symbol could not
/// be renamed (invalid name, unresolved reference), and [files] is then empty.
class RenameResultInfo {
  const RenameResultInfo({this.error = '', this.files = const []});

  factory RenameResultInfo.fromJson(Map<String, dynamic> json) {
    return RenameResultInfo(
      error: json['error'] as String? ?? '',
      files: (json['files'] as List<dynamic>? ?? [])
          .map(
            (item) => RenameFileEditInfo.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String error;
  final List<RenameFileEditInfo> files;

  bool get isEmpty => error.isEmpty && files.isEmpty;
}

class SignatureHelpInfo {
  const SignatureHelpInfo({
    required this.keyword,
    this.documentation = '',
    this.detail = '',
    this.activeParameter = 0,
    this.parameters = const [],
    this.sourceType = '',
    this.libraryName = '',
    this.deprecated = false,
  });

  factory SignatureHelpInfo.fromJson(Map<String, dynamic> json) {
    return SignatureHelpInfo(
      keyword: json['keyword'] as String,
      documentation: json['documentation'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      activeParameter: (json['active_parameter'] as num?)?.toInt() ?? 0,
      parameters: (json['parameters'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                SignatureParameterInfo.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      sourceType: json['source_type'] as String? ?? '',
      libraryName: json['library_name'] as String? ?? '',
      deprecated: json['deprecated'] as bool? ?? false,
    );
  }

  final String keyword;
  final String documentation;
  final String detail;
  final int activeParameter;
  final List<SignatureParameterInfo> parameters;
  final String sourceType;
  final String libraryName;
  final bool deprecated;
}

class EditorBreadcrumbInfo {
  const EditorBreadcrumbInfo({
    this.workspace,
    this.project,
    this.folder,
    this.fileName,
    this.symbol,
    this.segments = const [],
  });

  final String? workspace;
  final String? project;
  final String? folder;
  final String? fileName;
  final IndexedSymbolInfo? symbol;

  /// Clickable crumbs (project / folder / file / symbol).
  final List<BreadcrumbSegment> segments;
}

class BreadcrumbSegment {
  const BreadcrumbSegment({required this.label, this.path, this.line});

  final String label;
  final String? path;
  final int? line;
}

class FoldingRangeInfo {
  const FoldingRangeInfo({required this.startLine, required this.endLine});

  factory FoldingRangeInfo.fromJson(Map<String, dynamic> json) {
    return FoldingRangeInfo(
      startLine: (json['start_line'] as num?)?.toInt() ?? 0,
      endLine: (json['end_line'] as num?)?.toInt() ?? 0,
    );
  }

  /// 0-based inclusive line range.
  final int startLine;
  final int endLine;
}

class DocumentSymbolNode {
  const DocumentSymbolNode({
    required this.id,
    required this.name,
    required this.kind,
    required this.line,
    this.endLine,
    this.column = 1,
    this.detail = '',
    this.documentation = '',
    this.children = const [],
  });

  factory DocumentSymbolNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = <DocumentSymbolNode>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        if (item is Map<String, dynamic>) {
          children.add(DocumentSymbolNode.fromJson(item));
        }
      }
    }
    final name = json['name'] as String? ?? '';
    final kind = SymbolKind.fromApi(json['kind'] as String? ?? 'keyword');
    final line = (json['line'] as num?)?.toInt() ?? 1;
    final id = json['id'] as String? ?? '${kind.apiValue}:$line:$name';
    return DocumentSymbolNode(
      id: id,
      name: name,
      kind: kind,
      line: line,
      endLine: (json['end_line'] as num?)?.toInt() ?? line,
      column: (json['column'] as num?)?.toInt() ?? 1,
      detail: json['detail'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      children: children,
    );
  }

  final String id;
  final String name;
  final SymbolKind kind;
  final int line;
  final int? endLine;
  final int column;
  final String detail;
  final String documentation;
  final List<DocumentSymbolNode> children;

  bool get hasChildren => children.isNotEmpty;

  Iterable<DocumentSymbolNode> walk() sync* {
    yield this;
    for (final child in children) {
      yield* child.walk();
    }
  }

  DocumentSymbolNode? findAtLine(int line) {
    final end = endLine ?? this.line;
    if (line < this.line || line > end) return null;
    DocumentSymbolNode? best = this;
    for (final child in children) {
      final hit = child.findAtLine(line);
      if (hit != null) best = hit;
    }
    return best;
  }

  IndexedSymbolInfo toIndexed(String filePath) {
    return IndexedSymbolInfo(
      id: id,
      name: name,
      kind: kind,
      filePath: filePath,
      line: line,
      column: column,
      documentation: documentation,
      detail: detail,
    );
  }
}

class DocumentAnalysisInfo {
  const DocumentAnalysisInfo({
    required this.filePath,
    required this.root,
    this.contentHash = '',
    this.foldingRanges = const [],
  });

  factory DocumentAnalysisInfo.fromJson(Map<String, dynamic> json) {
    final rootRaw = json['root'];
    final root = rootRaw is Map<String, dynamic>
        ? DocumentSymbolNode.fromJson(rootRaw)
        : const DocumentSymbolNode(
            id: 'empty',
            name: '',
            kind: SymbolKind.file,
            line: 1,
          );
    final ranges = <FoldingRangeInfo>[];
    final rawRanges = json['folding_ranges'];
    if (rawRanges is List) {
      for (final item in rawRanges) {
        if (item is Map<String, dynamic>) {
          ranges.add(FoldingRangeInfo.fromJson(item));
        }
      }
    }
    return DocumentAnalysisInfo(
      filePath: json['file_path'] as String? ?? '',
      contentHash: json['content_hash'] as String? ?? '',
      root: root,
      foldingRanges: ranges,
    );
  }

  final String filePath;
  final String contentHash;
  final DocumentSymbolNode root;
  final List<FoldingRangeInfo> foldingRanges;

  List<IndexedSymbolInfo> flattenIndexed() {
    return root
        .walk()
        .map((node) => node.toIndexed(filePath))
        .toList(growable: false);
  }
}
