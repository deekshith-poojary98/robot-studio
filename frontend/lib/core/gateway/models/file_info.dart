class FileContentInfo {
  const FileContentInfo({
    required this.path,
    required this.content,
    required this.mtime,
    this.size = 0,
  });

  factory FileContentInfo.fromJson(Map<String, dynamic> json) {
    return FileContentInfo(
      path: json['path'] as String,
      content: json['content'] as String? ?? '',
      mtime: (json['mtime'] as num).toDouble(),
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String path;
  final String content;
  final double mtime;
  final int size;
}

class FileWriteResult {
  const FileWriteResult({
    required this.path,
    required this.mtime,
    this.size = 0,
    this.savedAt,
  });

  factory FileWriteResult.fromJson(Map<String, dynamic> json) {
    return FileWriteResult(
      path: json['path'] as String,
      mtime: (json['mtime'] as num).toDouble(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      savedAt: json['saved_at'] as String?,
    );
  }

  final String path;
  final double mtime;
  final int size;
  final String? savedAt;
}

class FileTreeNode {
  const FileTreeNode({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDir,
    this.suffix = '',
    this.children = const [],
  });

  factory FileTreeNode.fromJson(Map<String, dynamic> json) {
    final kids = (json['children'] as List<dynamic>? ?? [])
        .map((item) => FileTreeNode.fromJson(item as Map<String, dynamic>))
        .toList();
    return FileTreeNode(
      name: json['name'] as String,
      path: json['path'] as String,
      relativePath: json['relative_path'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      suffix: json['suffix'] as String? ?? '',
      children: kids,
    );
  }

  final String name;
  final String path;
  final String relativePath;
  final bool isDir;
  final String suffix;
  final List<FileTreeNode> children;

  bool get isRobotSource =>
      suffix == '.robot' || suffix == '.resource' || suffix == '.py';
}

class EditorTabInfo {
  EditorTabInfo({
    required this.path,
    required this.content,
    required this.savedContent,
    required this.mtime,
    this.cursorLine = 1,
    this.cursorColumn = 1,
  });

  final String path;
  String content;
  String savedContent;
  double mtime;
  int cursorLine;
  int cursorColumn;

  bool get isDirty => content != savedContent;

  String get fileName {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }
}
