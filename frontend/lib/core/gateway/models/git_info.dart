import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum GitFileStatus {
  modified,
  added,
  deleted,
  renamed,
  untracked,
  copied;

  factory GitFileStatus.fromApi(String value) {
    return GitFileStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => GitFileStatus.modified,
    );
  }

  String get label => switch (this) {
        GitFileStatus.modified => 'Modified',
        GitFileStatus.added => 'Added',
        GitFileStatus.deleted => 'Deleted',
        GitFileStatus.renamed => 'Renamed',
        GitFileStatus.untracked => 'Untracked',
        GitFileStatus.copied => 'Copied',
      };

  String get badge => switch (this) {
        GitFileStatus.modified => 'M',
        GitFileStatus.added => 'A',
        GitFileStatus.deleted => 'D',
        GitFileStatus.renamed => 'R',
        GitFileStatus.untracked => 'U',
        GitFileStatus.copied => 'C',
      };

  Color get color => switch (this) {
        GitFileStatus.modified => AppColors.warning,
        GitFileStatus.added => AppColors.success,
        GitFileStatus.deleted => AppColors.error,
        GitFileStatus.renamed => AppColors.info,
        GitFileStatus.untracked => AppColors.textMuted,
        GitFileStatus.copied => AppColors.accent,
      };
}

class GitRepositoryInfo {
  const GitRepositoryInfo({
    required this.isRepository,
    this.root,
    this.branch,
    this.head,
    this.detached = false,
    this.clean = true,
  });

  factory GitRepositoryInfo.fromJson(Map<String, dynamic> json) {
    return GitRepositoryInfo(
      isRepository: json['is_repository'] as bool? ?? false,
      root: json['root'] as String?,
      branch: json['branch'] as String?,
      head: json['head'] as String?,
      detached: json['detached'] as bool? ?? false,
      clean: json['clean'] as bool? ?? true,
    );
  }

  final bool isRepository;
  final String? root;
  final String? branch;
  final String? head;
  final bool detached;
  final bool clean;
}

class GitFileChangeInfo {
  const GitFileChangeInfo({
    required this.path,
    required this.status,
    this.oldPath,
  });

  factory GitFileChangeInfo.fromJson(Map<String, dynamic> json) {
    return GitFileChangeInfo(
      path: json['path'] as String,
      status: GitFileStatus.fromApi(json['status'] as String? ?? 'modified'),
      oldPath: json['old_path'] as String?,
    );
  }

  final String path;
  final GitFileStatus status;
  final String? oldPath;
}

class GitStatusInfo {
  const GitStatusInfo({
    required this.repository,
    this.changes = const [],
  });

  factory GitStatusInfo.fromJson(Map<String, dynamic> json) {
    final changes = (json['changes'] as List<dynamic>? ?? [])
        .map((item) => GitFileChangeInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    return GitStatusInfo(
      repository: GitRepositoryInfo.fromJson(
        json['repository'] as Map<String, dynamic>? ?? const {},
      ),
      changes: changes,
    );
  }

  final GitRepositoryInfo repository;
  final List<GitFileChangeInfo> changes;
}

class GitCommitInfo {
  const GitCommitInfo({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.email,
    required this.date,
    required this.message,
  });

  factory GitCommitInfo.fromJson(Map<String, dynamic> json) {
    return GitCommitInfo(
      hash: json['hash'] as String,
      shortHash: json['short_hash'] as String,
      author: json['author'] as String,
      email: json['email'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      message: json['message'] as String,
    );
  }

  final String hash;
  final String shortHash;
  final String author;
  final String email;
  final DateTime date;
  final String message;
}

class GitCommitDetailInfo extends GitCommitInfo {
  const GitCommitDetailInfo({
    required super.hash,
    required super.shortHash,
    required super.author,
    required super.email,
    required super.date,
    required super.message,
    this.files = const [],
  });

  factory GitCommitDetailInfo.fromJson(Map<String, dynamic> json) {
    final files = (json['files'] as List<dynamic>? ?? [])
        .map((item) => GitFileChangeInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    return GitCommitDetailInfo(
      hash: json['hash'] as String,
      shortHash: json['short_hash'] as String,
      author: json['author'] as String,
      email: json['email'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      message: json['message'] as String,
      files: files,
    );
  }

  final List<GitFileChangeInfo> files;
}

class GitBranchInfo {
  const GitBranchInfo({
    required this.name,
    this.current = false,
    this.remote = false,
  });

  factory GitBranchInfo.fromJson(Map<String, dynamic> json) {
    return GitBranchInfo(
      name: json['name'] as String,
      current: json['current'] as bool? ?? false,
      remote: json['remote'] as bool? ?? false,
    );
  }

  final String name;
  final bool current;
  final bool remote;
}

class GitDiffLineInfo {
  const GitDiffLineInfo({
    required this.kind,
    this.left = '',
    this.right = '',
    this.leftLine,
    this.rightLine,
  });

  factory GitDiffLineInfo.fromJson(Map<String, dynamic> json) {
    return GitDiffLineInfo(
      kind: json['kind'] as String? ?? 'context',
      left: json['left'] as String? ?? '',
      right: json['right'] as String? ?? '',
      leftLine: json['left_line'] as int?,
      rightLine: json['right_line'] as int?,
    );
  }

  final String kind;
  final String left;
  final String right;
  final int? leftLine;
  final int? rightLine;
}

class GitDiffInfo {
  const GitDiffInfo({
    this.filePath,
    this.oldPath,
    this.lines = const [],
  });

  factory GitDiffInfo.fromJson(Map<String, dynamic> json) {
    final lines = (json['lines'] as List<dynamic>? ?? [])
        .map((item) => GitDiffLineInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    return GitDiffInfo(
      filePath: json['file_path'] as String?,
      oldPath: json['old_path'] as String?,
      lines: lines,
    );
  }

  final String? filePath;
  final String? oldPath;
  final List<GitDiffLineInfo> lines;
}

class GitRemoteResultInfo {
  const GitRemoteResultInfo({
    required this.success,
    this.message = '',
    this.output = '',
  });

  factory GitRemoteResultInfo.fromJson(Map<String, dynamic> json) {
    return GitRemoteResultInfo(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      output: json['output'] as String? ?? '',
    );
  }

  final bool success;
  final String message;
  final String output;
}
