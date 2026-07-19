import 'package:flutter/foundation.dart';

/// Debug-oriented logger for Robot Studio.
///
/// Logs only when [enabled] is true (defaults to [kDebugMode]).
/// Use from Gateway and AppShell to diagnose desktop runtime issues.
class AppLogger {
  AppLogger._();

  /// When false, all logging is a no-op. Defaults to debug builds only.
  static bool enabled = kDebugMode;

  static void debug(
    String message, {
    String tag = 'App',
    Object? data,
  }) {
    _log('DEBUG', tag, message, data: data);
  }

  static void info(
    String message, {
    String tag = 'App',
    Object? data,
  }) {
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
          (key == 'content' || key.contains('password') || key.contains('token'))) {
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
    if (!enabled) return;

    final time = DateTime.now().toIso8601String().substring(11, 23);
    final buffer = StringBuffer('[$time][$level][$tag] $message');
    if (data != null) {
      buffer.write(' | $data');
    }
    debugPrint(buffer.toString());
    if (error != null) {
      debugPrint('  └─ error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  └─ stack: $stackTrace');
    }
  }
}
