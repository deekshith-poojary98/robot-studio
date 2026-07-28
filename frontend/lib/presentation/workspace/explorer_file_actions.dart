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
