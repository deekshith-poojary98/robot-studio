/// Backend connection settings for Robot Studio.
///
/// Defaults match local development. Integration tests override host/port via
/// `--dart-define=ROBOT_STUDIO_BACKEND_PORT=<port>`.
///
/// Packaged launches may also set a [runtimePort] when the preferred port is
/// busy — [BackendHost] allocates a free port and points the UI here.
class BackendConfig {
  BackendConfig._();

  static const String _defaultHost = '127.0.0.1';
  static const String _defaultPort = '8765';

  /// Preferred port from compile-time define (before any runtime allocation).
  static int get preferredPort {
    const raw = String.fromEnvironment(
      'ROBOT_STUDIO_BACKEND_PORT',
      defaultValue: _defaultPort,
    );
    return int.tryParse(raw) ?? 8765;
  }

  static int? _runtimePort;

  /// Port used for this process. Prefer [preferredPort] unless [BackendHost]
  /// (or a test) overrides it after dynamic allocation.
  static int get port => _runtimePort ?? preferredPort;

  /// Override the backend port for this process (e.g. after allocating a free
  /// port). Pass `null` to clear back to [preferredPort].
  static void setRuntimePort(int? value) {
    _runtimePort = value;
  }

  static String get host => const String.fromEnvironment(
        'ROBOT_STUDIO_BACKEND_HOST',
        defaultValue: _defaultHost,
      );

  static String get httpBaseUrl => 'http://$host:$port/api/v1';

  static String get wsExecutionUrl =>
      'ws://$host:$port/api/v1/execution/stream';

  static String get wsWorkspaceEventsUrl =>
      'ws://$host:$port/api/v1/workspace/events';
}
