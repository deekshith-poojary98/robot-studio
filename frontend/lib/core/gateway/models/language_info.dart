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
  });

  factory CompletionItemInfo.fromJson(Map<String, dynamic> json) {
    return CompletionItemInfo(
      label: json['label'] as String,
      kind: json['kind'] as String? ?? 'keyword',
      detail: json['detail'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
      insertText: json['insert_text'] as String? ?? json['label'] as String,
    );
  }

  final String label;
  final String kind;
  final String detail;
  final String documentation;
  final String insertText;
}

class DiagnosticInfo {
  const DiagnosticInfo({
    required this.severity,
    required this.filePath,
    required this.line,
    required this.column,
    required this.message,
    this.source = 'robot',
  });

  factory DiagnosticInfo.fromJson(Map<String, dynamic> json) {
    return DiagnosticInfo(
      severity: DiagnosticSeverity.fromApi(json['severity'] as String? ?? 'error'),
      filePath: json['file_path'] as String? ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? 'robot',
    );
  }

  final DiagnosticSeverity severity;
  final String filePath;
  final int line;
  final int column;
  final String message;
  final String source;

  String get fileName {
    final normalized = filePath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty || parts.last.isEmpty ? filePath : parts.last;
  }

  String get locationLabel => '$fileName:$line:$column';
}

class SignatureParameterInfo {
  const SignatureParameterInfo({
    required this.label,
    this.documentation = '',
  });

  factory SignatureParameterInfo.fromJson(Map<String, dynamic> json) {
    return SignatureParameterInfo(
      label: json['label'] as String? ?? '',
      documentation: json['documentation'] as String? ?? '',
    );
  }

  final String label;
  final String documentation;
}

class SignatureHelpInfo {
  const SignatureHelpInfo({
    required this.keyword,
    this.documentation = '',
    this.detail = '',
    this.activeParameter = 0,
    this.parameters = const [],
  });

  factory SignatureHelpInfo.fromJson(Map<String, dynamic> json) {
    return SignatureHelpInfo(
      keyword: json['keyword'] as String,
      documentation: json['documentation'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      activeParameter: (json['active_parameter'] as num?)?.toInt() ?? 0,
      parameters: (json['parameters'] as List<dynamic>? ?? [])
          .map((item) => SignatureParameterInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String keyword;
  final String documentation;
  final String detail;
  final int activeParameter;
  final List<SignatureParameterInfo> parameters;
}

class EditorBreadcrumbInfo {
  const EditorBreadcrumbInfo({
    this.workspace,
    this.project,
    this.folder,
    this.fileName,
    this.symbol,
  });

  final String? workspace;
  final String? project;
  final String? folder;
  final String? fileName;
  final IndexedSymbolInfo? symbol;
}
