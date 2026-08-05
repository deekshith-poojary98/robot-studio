import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Debug-oriented logger for Robot Studio.
///
/// Console output is gated by [consoleEnabled] (defaults to [kDebugMode]).
/// After [initFileLogging], every level is also appended under
/// `~/.robot-studio/logs/frontend-YYYY-MM-DD.log`, and files older than
/// [retention] are deleted so support can collect traces without filling disk.
class AppLogger {
  AppLogger._();

  /// When false, stdout logging is a no-op. Defaults to debug builds only.
  static bool consoleEnabled = kDebugMode;

  /// Back-compat alias used by older call sites / tests.
  static bool get enabled => consoleEnabled;
  static set enabled(bool value) => consoleEnabled = value;

  static const retention = Duration(days: 7);
  static IOSink? _sink;
  static File? _file;
  static Directory? _logsDirectory;
  static Future<void> _writeQueue = Future<void>.value();
  static bool _initialized = false;

  /// Directory used for daily frontend log files (null until [initFileLogging]).
  static Directory? get logsDirectory => _logsDirectory;

  /// Current day's log file (null until [initFileLogging]).
  static File? get logFile => _file;

  /// Open (or reopen) the daily frontend log under [logsDir] and purge stale files.
  ///
  /// Safe to call more than once; subsequent calls with the same directory are
  /// no-ops. Failures are swallowed — logging must never take down the app.
  static Future<void> initFileLogging({
    Directory? logsDir,
    Duration retention = AppLogger.retention,
    DateTime? now,
  }) async {
    try {
      final root = logsDir ?? defaultLogsDirectory();
      root.createSync(recursive: true);
      purgeOldLogs(root, retention: retention, now: now);
      final day = _dayStamp(now ?? DateTime.now());
      final file = File(
        '${root.path}${Platform.pathSeparator}frontend-$day.log',
      );
      // Already attached to today's file — keep the open sink.
      if (_initialized &&
          _file != null &&
          _file!.path == file.path &&
          _sink != null) {
        _logsDirectory = root;
        return;
      }
      await _sink?.flush();
      await _sink?.close();
      _sink = file.openWrite(mode: FileMode.append);
      _file = file;
      _logsDirectory = root;
      _initialized = true;
      // Bootstrap line always goes to the file (even when console is off).
      _writeLine(
        _format('INFO', 'Log', 'Frontend file logging → ${file.path}'),
        forceFile: true,
      );
    } catch (_) {
      // Best-effort — leave console-only.
    }
  }

  /// Resolve `~/.robot-studio/logs` the same way [BackendHost] resolves data.
  static Directory defaultLogsDirectory() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return Directory(
      '$home${Platform.pathSeparator}.robot-studio'
      '${Platform.pathSeparator}logs',
    );
  }

  /// Delete `frontend-` / `backend-` daily logs older than [retention].
  ///
  /// Prefers the date in the filename; falls back to mtime. Returns deleted paths.
  static List<File> purgeOldLogs(
    Directory directory, {
    Duration retention = AppLogger.retention,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final cutoff = clock.subtract(retention);
    final deleted = <File>[];
    if (!directory.existsSync()) return deleted;

    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.log')) continue;
      final ageAnchor = _fileAgeAnchor(entity) ?? entity.lastModifiedSync();
      if (!ageAnchor.isBefore(cutoff)) continue;
      try {
        entity.deleteSync();
        deleted.add(entity);
      } catch (_) {
        // Best-effort.
      }
    }
    return deleted;
  }

  /// Close the file sink (tests / shutdown). Console logging still works.
  static Future<void> closeFileLogging() async {
    try {
      await _writeQueue;
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {
      // Best-effort.
    }
    _sink = null;
    _file = null;
    _logsDirectory = null;
    _initialized = false;
    _writeQueue = Future<void>.value();
  }

  static void debug(String message, {String tag = 'App', Object? data}) {
    _log('DEBUG', tag, message, data: data);
  }

  static void info(String message, {String tag = 'App', Object? data}) {
    _log('INFO', tag, message, data: data);
  }

  static void warn(
    String message, {
    String tag = 'App',
    Object? data,
    Object? error,
  }) {
    _log('WARN', tag, message, data: data, error: error);
  }

  static void error(
    String message, {
    String tag = 'App',
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      'ERROR',
      tag,
      message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Mirror AppShell console lines (`[info]`, `[warn]`, `[error]`) to stdout.
  static void fromConsoleLine(String line, {String tag = 'Shell'}) {
    if (line.startsWith('[error]')) {
      error(line.substring(7).trimLeft(), tag: tag);
    } else if (line.startsWith('[warn]')) {
      warn(line.substring(6).trimLeft(), tag: tag);
    } else if (line.startsWith('[info]')) {
      info(line.substring(6).trimLeft(), tag: tag);
    } else {
      debug(line, tag: tag);
    }
  }

  static String summarizeBody(Map<String, dynamic> body) {
    final copy = <String, dynamic>{};
    body.forEach((key, value) {
      if (value is String &&
          (key == 'content' ||
              key.contains('password') ||
              key.contains('token'))) {
        copy[key] = '<${value.length} chars>';
      } else if (value is String && value.length > 200) {
        copy[key] = '${value.substring(0, 200)}…<${value.length} chars>';
      } else {
        copy[key] = value;
      }
    });
    return copy.toString();
  }

  static void _log(
    String level,
    String tag,
    String message, {
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final line = _format(level, tag, message, data: data);
    final buffer = StringBuffer(line);
    if (error != null) {
      buffer.writeln();
      buffer.write('  └─ error: $error');
    }
    if (stackTrace != null) {
      buffer.writeln();
      buffer.write('  └─ stack: $stackTrace');
    }
    final text = buffer.toString();

    if (consoleEnabled) {
      debugPrint(text);
    }
    _writeLine(text);
  }

  static String _format(
    String level,
    String tag,
    String message, {
    Object? data,
  }) {
    final time = DateTime.now().toIso8601String().substring(11, 23);
    final buffer = StringBuffer('[$time][$level][$tag] $message');
    if (data != null) {
      buffer.write(' | $data');
    }
    return buffer.toString();
  }

  static void _writeLine(String text, {bool forceFile = false}) {
    final sink = _sink;
    if (sink == null && !forceFile) return;
    if (sink == null) return;
    _writeQueue = _writeQueue
        .then((_) async {
          sink.writeln(text);
        })
        .catchError((_) {});
  }

  static String _dayStamp(DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? _fileAgeAnchor(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path.split(Platform.pathSeparator).last
        : file.uri.pathSegments.last;
    final match = RegExp(
      r'^(backend|frontend)-(\d{4})-(\d{2})-(\d{2})\.log$',
    ).firstMatch(name);
    if (match == null) return null;
    final year = int.tryParse(match.group(2)!);
    final month = int.tryParse(match.group(3)!);
    final day = int.tryParse(match.group(4)!);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}
