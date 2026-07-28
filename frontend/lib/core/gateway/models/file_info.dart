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

class FileMutationResult {
  const FileMutationResult({
    required this.path,
    this.oldPath,
    this.isDir = false,
    this.name,
    this.deleted = false,
    this.mtime,
    this.size,
    this.savedAt,
  });

  factory FileMutationResult.fromJson(Map<String, dynamic> json) {
    return FileMutationResult(
      path: json['path'] as String,
      oldPath: json['old_path'] as String?,
      isDir: json['is_dir'] as bool? ?? false,
      name: json['name'] as String?,
      deleted: json['deleted'] as bool? ?? false,
      mtime: (json['mtime'] as num?)?.toDouble(),
      size: (json['size'] as num?)?.toInt(),
      savedAt: json['saved_at'] as String?,
    );
  }

  final String path;
  final String? oldPath;
  final bool isDir;
  final String? name;
  final bool deleted;
  final double? mtime;
  final int? size;
  final String? savedAt;
}

class FileTreeNode {
  const FileTreeNode({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDir,
    this.suffix = '',
    this.hasChildren = false,
    this.children = const [],
  });

  factory FileTreeNode.fromJson(Map<String, dynamic> json) {
    final kids = (json['children'] as List<dynamic>? ?? [])
        .map((item) => FileTreeNode.fromJson(item as Map<String, dynamic>))
        .toList();
    final isDir = json['is_dir'] as bool? ?? false;
    return FileTreeNode(
      name: json['name'] as String,
      path: json['path'] as String,
      relativePath: json['relative_path'] as String? ?? '',
      isDir: isDir,
      suffix: json['suffix'] as String? ?? '',
      hasChildren: json['has_children'] as bool? ?? (isDir && kids.isNotEmpty),
      children: kids,
    );
  }

  final String name;
  final String path;
  final String relativePath;
  final bool isDir;
  final String suffix;
  final bool hasChildren;
  final List<FileTreeNode> children;

  bool get isRobotSource =>
      suffix == '.robot' || suffix == '.resource' || suffix == '.py';

  FileTreeNode copyWith({bool? hasChildren, List<FileTreeNode>? children}) {
    return FileTreeNode(
      name: name,
      path: path,
      relativePath: relativePath,
      isDir: isDir,
      suffix: suffix,
      hasChildren: hasChildren ?? this.hasChildren,
      children: children ?? this.children,
    );
  }
}

/// One visible row in the VS Code-style virtualized explorer.
class FlatFileTreeRow {
  const FlatFileTreeRow({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.loading,
  });

  final FileTreeNode node;
  final int depth;
  final bool expanded;
  final bool loading;
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
