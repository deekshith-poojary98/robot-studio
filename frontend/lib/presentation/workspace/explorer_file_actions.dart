import 'dart:io';

/// Client-side name validation and Robot filename suggestions for Explorer.
class ExplorerFileActions {
  ExplorerFileActions._();

  static final _invalidChars = RegExp(r'[<>:"|?*\x00-\x1f]');
  static const _reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// Returns null when valid; otherwise a friendly message.
  static String? validateName(
    String name, {
    Iterable<String> existingNames = const [],
  }) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'Name cannot be empty';
    if (cleaned != name) return 'Name cannot start or end with spaces';
    if (cleaned == '.' || cleaned == '..') return 'Name is not allowed';
    if (cleaned.contains('/') || cleaned.contains('\\')) {
      return 'Name cannot contain path separators';
    }
    if (_invalidChars.hasMatch(cleaned)) {
      return 'Name contains invalid characters';
    }
    if (cleaned.endsWith('.')) return 'Name cannot end with a dot';
    final stem = cleaned.split('.').first.toUpperCase();
    if (_reserved.contains(stem)) return "'$cleaned' is a reserved name";
    final lower = cleaned.toLowerCase();
    for (final existing in existingNames) {
      if (existing.toLowerCase() == lower) {
        return 'A file or folder with this name already exists';
      }
    }
    return null;
  }

  /// Suggests `Login.robot` when the user types `Login` with no extension.
  static String? robotSuggestion(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.contains('.')) return null;
    return '$cleaned.robot';
  }

  /// Default suite scaffold for newly created empty `*.robot` files.
  static const defaultRobotSuiteContent = '''*** Settings ***
Documentation    Test suite description
Library          BuiltIn

*** Variables ***

*** Test Cases ***
Example Test
    [Documentation]    Example test case
    Log    Hello, Robot Framework!

*** Keywords ***
Example Keyword
    [Documentation]    Example reusable keyword
    Log    Keyword executed
''';

  /// Returns [defaultRobotSuiteContent] for `.robot` paths; otherwise empty.
  static String initialContentFor(String nameOrPath) {
    final lower = nameOrPath.replaceAll('\\', '/').toLowerCase();
    if (lower.endsWith('.robot')) return defaultRobotSuiteContent;
    return '';
  }

  static String joinPath(String parent, String name) {
    final left = parent.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    return '$left/$name';
  }

  static String parentPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return normalized;
    return normalized.substring(0, index);
  }

  static String basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  /// Drops children when an ancestor is also selected (VS Code-style).
  ///
  /// Used before multi-delete / multi-move so deleting a folder does not also
  /// try to delete files nested under it.
  static List<String> pruneNestedPaths(Iterable<String> paths) {
    final normalized =
        paths
            .map((path) => path.replaceAll('\\', '/'))
            .where((path) => path.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final kept = <String>[];
    for (final path in normalized) {
      final covered = kept.any(
        (parent) => path == parent || path.startsWith('$parent/'),
      );
      if (!covered) kept.add(path);
    }
    return kept;
  }

  /// Short path for UI tips: `/Users/me/proj/a.robot` → `~/proj/a.robot`.
  /// Leaves paths outside the home directory unchanged.
  static String homeRelativePath(String path, {String? home}) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) return normalized;
    final homeRaw =
        home ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (homeRaw == null || homeRaw.isEmpty) return normalized;
    var homeNorm = homeRaw.replaceAll('\\', '/');
    if (homeNorm.endsWith('/') && homeNorm.length > 1) {
      homeNorm = homeNorm.substring(0, homeNorm.length - 1);
    }
    if (normalized == homeNorm ||
        normalized.toLowerCase() == homeNorm.toLowerCase()) {
      return '~';
    }
    final prefix = '$homeNorm/';
    if (normalized.startsWith(prefix)) {
      return '~/${normalized.substring(prefix.length)}';
    }
    if (normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
      return '~/${normalized.substring(prefix.length)}';
    }
    return normalized;
  }

  static String revealLabel() {
    if (Platform.isMacOS) return 'Reveal in Finder';
    if (Platform.isWindows) return 'Reveal in Explorer';
    return 'Reveal in File Manager';
  }

  static Future<void> revealInOs(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
      return;
    }
    final parent = parentPath(path);
    await Process.run('xdg-open', [parent]);
  }
}
