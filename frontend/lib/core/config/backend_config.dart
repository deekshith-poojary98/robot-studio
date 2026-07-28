/// Backend connection settings for Robot Studio.
///
/// Defaults match local development. Integration tests override host/port via
/// `--dart-define=ROBOT_STUDIO_BACKEND_PORT=<port>`.
class BackendConfig {
  BackendConfig._();

  static const String _defaultHost = '127.0.0.1';
  static const String _defaultPort = '8765';

  static String get host => const String.fromEnvironment(
        'ROBOT_STUDIO_BACKEND_HOST',
        defaultValue: _defaultHost,
      );

  static int get port {
    const raw = String.fromEnvironment(
      'ROBOT_STUDIO_BACKEND_PORT',
      defaultValue: _defaultPort,
    );
    return int.tryParse(raw) ?? 8765;
  }

  static String get httpBaseUrl => 'http://$host:$port/api/v1';

  static String get wsExecutionUrl =>
      'ws://$host:$port/api/v1/execution/stream';

  static String get wsWorkspaceEventsUrl =>
      'ws://$host:$port/api/v1/workspace/events';
}
