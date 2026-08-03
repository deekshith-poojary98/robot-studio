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
///   do nothing — unless a leftover packaged-sidecar PID file is present, in
///   which case we reclaim ownership so Quit can stop it.
/// - Else if a sidecar binary sits next to the app, spawn it and wait for health.
/// - Else leave the UI to show BACKEND UNAVAILABLE (dev without a running API).
///
/// Quit cleanup: Flutter lifecycle `detached` is unreliable on macOS desktop, so
/// we also write `~/.robot-studio/backend.pid` for the native runner to kill on
/// `applicationWillTerminate`.
class BackendHost {
  BackendHost._({
    this.process,
    this.pid,
    this.startedByApp = false,
  });

  final Process? process;
  final int? pid;
  final bool startedByApp;

  static const _sidecarName = 'robot-studio-backend';
  static const pidFileName = 'backend.pid';
  static BackendHost? _instance;

  static BackendHost? get instance => _instance;

  int? get ownedPid => process?.pid ?? pid;

  /// Start or attach before [runApp]. Safe to call once.
  static Future<BackendHost> ensureStarted({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_instance != null) return _instance!;

    final healthUrl = '${BackendConfig.httpBaseUrl}/health';
    final sidecar = resolveSidecarPath();
    final existingPid = readPidFile();

    if (await waitForHealth(healthUrl, timeout: const Duration(seconds: 1))) {
      // Packaged orphan from a previous Quit that never killed the sidecar.
      if (sidecar != null &&
          existingPid != null &&
          _isPidAlive(existingPid)) {
        AppLogger.info(
          'Reclaiming leftover packaged backend',
          tag: 'BackendHost',
          data: existingPid,
        );
        return _instance = BackendHost._(
          pid: existingPid,
          startedByApp: true,
        );
      }
      AppLogger.info(
        'Backend already healthy — not spawning sidecar',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    // Stale pid file from a dead process.
    if (existingPid != null && !_isPidAlive(existingPid)) {
      clearPidFile();
    }

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

    writePidFile(process.pid);

    final ready = await waitForHealth(healthUrl, timeout: timeout);
    if (!ready) {
      _killPid(process.pid);
      clearPidFile();
      AppLogger.error(
        'Bundled backend failed to become ready within ${timeout.inSeconds}s',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    AppLogger.info('Bundled backend ready', tag: 'BackendHost');
    return _instance = BackendHost._(process: process, startedByApp: true);
  }

  /// Async stop used from Flutter lifecycle. Prefer [stopSync] from native quit.
  Future<void> stop() async {
    if (!startedByApp) return;
    final target = ownedPid;
    if (target == null) return;
    AppLogger.info('Stopping bundled backend', tag: 'BackendHost', data: target);
    _killPid(target);
    try {
      if (process != null) {
        await process!.exitCode.timeout(const Duration(seconds: 2));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } on TimeoutException {
      _killPid(target, force: true);
    }
    clearPidFile();
  }

  /// Synchronous kill for AppDelegate / last-chance quit hooks.
  void stopSync() {
    if (!startedByApp) return;
    final target = ownedPid;
    if (target == null) return;
    AppLogger.info(
      'Stopping bundled backend (sync)',
      tag: 'BackendHost',
      data: target,
    );
    _killPid(target);
    _killPid(target, force: true);
    clearPidFile();
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

  @visibleForTesting
  static File pidFile({Directory? dataDir}) {
    final root = dataDir ?? _dataDir();
    return File('${root.path}${(Platform.pathSeparator)}$pidFileName');
  }

  @visibleForTesting
  static void writePidFile(int processId, {Directory? dataDir}) {
    try {
      pidFile(dataDir: dataDir).writeAsStringSync('$processId\n');
    } catch (error) {
      AppLogger.debug('Could not write backend pid file: $error', tag: 'BackendHost');
    }
  }

  @visibleForTesting
  static int? readPidFile({Directory? dataDir}) {
    try {
      final file = pidFile(dataDir: dataDir);
      if (!file.existsSync()) return null;
      return int.tryParse(file.readAsStringSync().trim());
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void clearPidFile({Directory? dataDir}) {
    try {
      final file = pidFile(dataDir: dataDir);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort.
    }
  }

  static Directory _dataDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home${Platform.pathSeparator}.robot-studio');
    dir.createSync(recursive: true);
    return dir;
  }

  static bool _isPidAlive(int processId) {
    if (processId <= 0) return false;
    try {
      if (Platform.isWindows) {
        final result = Process.runSync(
          'tasklist',
          ['/FI', 'PID eq $processId', '/NH'],
          runInShell: true,
        );
        return result.stdout.toString().contains('$processId');
      }
      // POSIX: signal 0 checks existence without delivering a signal.
      final result = Process.runSync('kill', ['-0', '$processId']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static void _killPid(int processId, {bool force = false}) {
    final signal = force ? ProcessSignal.sigkill : ProcessSignal.sigterm;
    try {
      Process.killPid(processId, signal);
    } catch (_) {
      // Already gone.
    }
    // PyInstaller / uvicorn may leave children; best-effort process-group kill.
    if (!Platform.isWindows) {
      try {
        Process.killPid(-processId, signal);
      } catch (_) {
        // Not a group leader — fine.
      }
      if (force) {
        try {
          Process.runSync('pkill', ['-KILL', '-P', '$processId']);
        } catch (_) {
          // pkill may be unavailable.
        }
      }
    }
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
