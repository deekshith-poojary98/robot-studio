import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'config/backend_config.dart';
import 'logging/app_logger.dart';

/// Owns the bundled Python sidecar for double-click desktop launches.
///
/// Behavior:
/// - If the backend is already healthy on the preferred (or last-used) port
///   (e.g. `make backend` in development), attach — and reclaim a leftover
///   packaged-sidecar PID so Quit can stop it.
/// - Else if a sidecar binary sits next to the app, allocate a free port
///   (preferred first, then nearby), spawn it, and point [BackendConfig] there.
/// - Else leave the UI to show BACKEND UNAVAILABLE (dev without a running API).
///
/// Quit cleanup: Flutter lifecycle `detached` is unreliable on desktop, so
/// we also write `~/.robot-studio/backend.pid` (and `backend.port`) for the
/// native runner to kill on quit (macOS `applicationWillTerminate`, Windows
/// `OnDestroy`, Linux shutdown).
class BackendHost {
  BackendHost._({this.process, this.pid, this.startedByApp = false});

  final Process? process;
  final int? pid;
  final bool startedByApp;

  static const _sidecarName = 'robot-studio-backend';
  static const pidFileName = 'backend.pid';
  static const portFileName = 'backend.port';
  static const _portSearchWindow = 50;
  static BackendHost? _instance;
  static DateTime? _lastRestartAt;

  static BackendHost? get instance => _instance;

  int? get ownedPid => process?.pid ?? pid;

  /// Start or attach before [runApp]. Safe to call once.
  static Future<BackendHost> ensureStarted({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_instance != null) return _instance!;

    final preferred = BackendConfig.preferredPort;
    final sidecar = resolveSidecarPath();
    final existingPid = readPidFile();
    final rememberedPort = readPortFile();

    // Prefer an already-healthy preferred port (dev: make backend).
    if (await waitForHealth(
      _healthUrl(preferred),
      timeout: const Duration(seconds: 1),
    )) {
      return _attachExisting(
        port: preferred,
        sidecar: sidecar,
        existingPid: existingPid,
      );
    }

    // Packaged orphan may be on a dynamically allocated port.
    if (rememberedPort != null &&
        rememberedPort != preferred &&
        await waitForHealth(
          _healthUrl(rememberedPort),
          timeout: const Duration(seconds: 1),
        )) {
      return _attachExisting(
        port: rememberedPort,
        sidecar: sidecar,
        existingPid: existingPid,
      );
    }

    // Stale pid / port files from a dead process.
    if (existingPid != null && !_isPidAlive(existingPid)) {
      clearPidFile();
      clearPortFile();
    }

    if (sidecar == null) {
      BackendConfig.setRuntimePort(preferred);
      AppLogger.info(
        'No bundled sidecar found — waiting for an external backend '
        '(dev: make backend)',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    final port = await allocatePort(
      host: BackendConfig.host,
      preferred: preferred,
    );
    BackendConfig.setRuntimePort(port);
    if (port != preferred) {
      AppLogger.info(
        'Preferred port $preferred busy — using $port',
        tag: 'BackendHost',
      );
    }

    AppLogger.info(
      'Starting sidecar on :$port',
      tag: 'BackendHost',
      data: sidecar,
    );
    final dataDir = _dataDir();
    final process = await Process.start(
      sidecar,
      const [],
      environment: {
        ...Platform.environment,
        'ROBOT_STUDIO_HOST': BackendConfig.host,
        'ROBOT_STUDIO_PORT': '$port',
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
    // Uvicorn access logs use stdout. Process.start pipes stdout even when the
    // child is a windowed PyInstaller executable; if nobody consumes that
    // pipe, it fills and blocks the backend event loop in logging.flush().
    // Backend access logs are already persisted by the sidecar, so discard
    // this copy while keeping the pipe drained.
    process.stdout.listen((_) {}, onError: (_) {});

    writePidFile(process.pid);
    writePortFile(port);

    final ready = await waitForHealth(_healthUrl(port), timeout: timeout);
    if (!ready) {
      _killPid(process.pid);
      clearPidFile();
      clearPortFile();
      AppLogger.error(
        'Bundled backend failed to become ready within ${timeout.inSeconds}s',
        tag: 'BackendHost',
      );
      return _instance = BackendHost._();
    }

    AppLogger.info('Bundled backend ready on :$port', tag: 'BackendHost');
    return _instance = BackendHost._(process: process, startedByApp: true);
  }

  static BackendHost _attachExisting({
    required int port,
    required String? sidecar,
    required int? existingPid,
  }) {
    BackendConfig.setRuntimePort(port);
    writePortFile(port);
    if (sidecar != null && existingPid != null && _isPidAlive(existingPid)) {
      AppLogger.info(
        'Reclaiming leftover packaged backend',
        tag: 'BackendHost',
        data: 'pid=$existingPid port=$port',
      );
      writePidFile(existingPid);
      return _instance = BackendHost._(pid: existingPid, startedByApp: true);
    }
    AppLogger.info(
      'Backend already healthy on :$port — not spawning sidecar',
      tag: 'BackendHost',
    );
    return _instance = BackendHost._();
  }

  static String _healthUrl(int port) =>
      'http://${BackendConfig.host}:$port/api/v1/health';

  /// Bind-probe for a free TCP port, preferring [preferred] then nearby ports.
  @visibleForTesting
  static Future<int> allocatePort({
    required String host,
    required int preferred,
    int searchWindow = _portSearchWindow,
  }) async {
    final start = preferred.clamp(1, 65535);
    for (var i = 0; i < searchWindow; i++) {
      final candidate = start + i;
      if (candidate > 65535) break;
      if (await _canBind(host, candidate)) {
        return candidate;
      }
    }
    // Last resort: OS-assigned ephemeral port.
    final server = await ServerSocket.bind(host, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  static Future<bool> _canBind(String host, int port) async {
    try {
      final server = await ServerSocket.bind(host, port);
      await server.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kill a frozen or dead owned sidecar and spawn a fresh one.
  ///
  /// Used when health probes fail while the UI still owns the backend process.
  /// Cooldown prevents restart loops when the host is genuinely misconfigured.
  static Future<bool> restartOwnedSidecar({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final current = _instance;
    if (current == null || !current.startedByApp) return false;
    final now = DateTime.now();
    if (_lastRestartAt != null &&
        now.difference(_lastRestartAt!) < const Duration(seconds: 60)) {
      return false;
    }

    final target = current.ownedPid;
    AppLogger.warn(
      'Restarting bundled backend after health failure',
      tag: 'BackendHost',
      data: target,
    );
    if (target != null) {
      _killPid(target, force: true);
    }
    clearPidFile();
    clearPortFile();
    _instance = null;
    _lastRestartAt = now;

    final host = await ensureStarted(timeout: timeout);
    return host.startedByApp && host.ownedPid != null;
  }

  /// Async stop used from Flutter lifecycle. Prefer [stopSync] from native quit.
  Future<void> stop() async {
    if (!startedByApp) return;
    final target = ownedPid;
    if (target == null) return;
    AppLogger.info(
      'Stopping bundled backend',
      tag: 'BackendHost',
      data: target,
    );
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
    clearPortFile();
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
    clearPortFile();
  }

  /// Locate the frozen sidecar next to the Flutter executable.
  @visibleForTesting
  static String? resolveSidecarPath({String? resolvedExecutable}) {
    final exe = resolvedExecutable ?? Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    final sep = Platform.pathSeparator;
    final names = Platform.isWindows
        ? <String>['$_sidecarName.exe', 'backend$sep$_sidecarName.exe']
        : <String>[_sidecarName, 'backend$sep$_sidecarName'];

    for (final name in names) {
      final candidate = '$dir$sep$name';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    // macOS: also check Resources/backend inside the .app bundle.
    if (Platform.isMacOS) {
      final resources =
          '$dir$sep..${sep}Resources${sep}backend$sep$_sidecarName';
      if (File(resources).existsSync()) {
        return File(resources).absolute.path;
      }
    }
    return null;
  }

  @visibleForTesting
  static File pidFile({Directory? dataDir}) {
    final root = dataDir ?? _dataDir();
    return File('${root.path}${Platform.pathSeparator}$pidFileName');
  }

  @visibleForTesting
  static File portFile({Directory? dataDir}) {
    final root = dataDir ?? _dataDir();
    return File('${root.path}${Platform.pathSeparator}$portFileName');
  }

  @visibleForTesting
  static void writePidFile(int processId, {Directory? dataDir}) {
    try {
      pidFile(dataDir: dataDir).writeAsStringSync('$processId\n');
    } catch (error) {
      AppLogger.debug(
        'Could not write backend pid file: $error',
        tag: 'BackendHost',
      );
    }
  }

  @visibleForTesting
  static void writePortFile(int port, {Directory? dataDir}) {
    try {
      portFile(dataDir: dataDir).writeAsStringSync('$port\n');
    } catch (error) {
      AppLogger.debug(
        'Could not write backend port file: $error',
        tag: 'BackendHost',
      );
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
  static int? readPortFile({Directory? dataDir}) {
    try {
      final file = portFile(dataDir: dataDir);
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

  @visibleForTesting
  static void clearPortFile({Directory? dataDir}) {
    try {
      final file = portFile(dataDir: dataDir);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort.
    }
  }

  static Directory _dataDir() {
    final home =
        Platform.environment['HOME'] ??
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
        final result = Process.runSync('tasklist', [
          '/FI',
          'PID eq $processId',
          '/NH',
        ], runInShell: true);
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
    if (Platform.isWindows) {
      final args = ['/PID', '$processId', '/T'];
      if (force) {
        args.add('/F');
      }
      try {
        Process.runSync('taskkill', args, runInShell: true);
      } catch (_) {
        // Already gone.
      }
      return;
    }

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
          final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
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
