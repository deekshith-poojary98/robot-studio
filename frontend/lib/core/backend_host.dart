import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'config/backend_config.dart';
import 'logging/app_logger.dart';

/// Owns the bundled Python sidecar for double-click desktop launches.
///
/// Behavior:
/// - If the backend is already healthy (e.g. `make backend` in development),
///   do nothing.
/// - Else if a sidecar binary sits next to the app, spawn it and wait for health.
/// - Else leave the UI to show BACKEND UNAVAILABLE (dev without a running API).
class BackendHost {
  BackendHost._({this.process, this.startedByApp = false});

  final Process? process;
  final bool startedByApp;

  static const _sidecarName = 'robot-studio-backend';
  static BackendHost? _instance;

  static BackendHost? get instance => _instance;

  /// Start or attach before [runApp]. Safe to call once.
  static Future<BackendHost> ensureStarted({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_instance != null) return _instance!;

    final healthUrl = '${BackendConfig.httpBaseUrl}/health';
    if (await waitForHealth(healthUrl, timeout: const Duration(seconds: 1))) {
      AppLogger.info(
        'Backend already healthy — not spawning sidecar',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    final sidecar = resolveSidecarPath();
    if (sidecar == null) {
      AppLogger.info(
        'No bundled sidecar found — waiting for an external backend '
        '(dev: make backend)',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    AppLogger.info('Starting sidecar', tag: 'BackendHost', data: sidecar);
    final dataDir = _dataDir();
    final process = await Process.start(
      sidecar,
      const [],
      environment: {
        ...Platform.environment,
        'ROBOT_STUDIO_HOST': BackendConfig.host,
        'ROBOT_STUDIO_PORT': '${BackendConfig.port}',
        'ROBOT_STUDIO_DATA_DIR': dataDir.path,
        'ROBOT_STUDIO_DEBUG': 'false',
      },
      workingDirectory: File(sidecar).parent.path,
    );

    process.stderr.transform(utf8.decoder).listen((chunk) {
      final line = chunk.trim();
      if (line.isNotEmpty) {
        AppLogger.debug(line, tag: 'Backend');
      }
    });

    final ready = await waitForHealth(healthUrl, timeout: timeout);
    if (!ready) {
      process.kill(ProcessSignal.sigterm);
      AppLogger.error(
        'Bundled backend failed to become ready within ${timeout.inSeconds}s',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    AppLogger.info('Bundled backend ready', tag: 'BackendHost');
    return _instance = BackendHost._(process: process, startedByApp: true);
  }

  Future<void> stop() async {
    if (!startedByApp || process == null) return;
    AppLogger.info('Stopping bundled backend', tag: 'BackendHost');
    process!.kill(ProcessSignal.sigterm);
    try {
      await process!.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process!.kill(ProcessSignal.sigkill);
    }
  }

  /// Locate the frozen sidecar next to the Flutter executable.
  @visibleForTesting
  static String? resolveSidecarPath({String? resolvedExecutable}) {
    final exe = resolvedExecutable ?? Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    final sep = Platform.pathSeparator;
    final names = Platform.isWindows
        ? <String>[
            '$_sidecarName.exe',
            'backend$sep$_sidecarName.exe',
          ]
        : <String>[
            _sidecarName,
            'backend$sep$_sidecarName',
          ];

    for (final name in names) {
      final candidate = '$dir$sep$name';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    // macOS: also check Resources/backend inside the .app bundle.
    if (Platform.isMacOS) {
      final resources =
          '$dir${sep}..${sep}Resources${sep}backend$sep$_sidecarName';
      if (File(resources).existsSync()) {
        return File(resources).absolute.path;
      }
    }
    return null;
  }

  static Directory _dataDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home${Platform.pathSeparator}.robot-studio');
    dir.createSync(recursive: true);
    return dir;
  }

  static Future<bool> waitForHealth(
    String url, {
    required Duration timeout,
  }) async {
    final client = HttpClient();
    final deadline = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client
              .getUrl(Uri.parse(url))
              .timeout(const Duration(seconds: 2));
          final response =
              await request.close().timeout(const Duration(seconds: 2));
          await response.drain<void>();
          if (response.statusCode == 200) {
            return true;
          }
        } catch (_) {
          // Still starting.
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
