import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/backend_host.dart';
import 'core/gateway/transport_gateway.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initFileLogging();
  AppLogger.info(
    'Robot Studio starting',
    tag: 'Main',
    data: kDebugMode ? 'debug' : 'release',
  );

  FlutterError.onError = (details) {
    AppLogger.error(
      'FlutterError: ${details.exceptionAsString()}',
      tag: 'Flutter',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error(
      'Uncaught async error',
      tag: 'Flutter',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  // Double-click launches must bring up the bundled sidecar themselves.
  // In development (`flutter run` + `make backend`), health is already OK.
  try {
    await BackendHost.ensureStarted();
  } catch (error, stackTrace) {
    AppLogger.error(
      'Backend host failed to start',
      tag: 'Main',
      error: error,
      stackTrace: stackTrace,
    );
  }

  runApp(const RobotStudioApp());
}

class RobotStudioApp extends StatefulWidget {
  const RobotStudioApp({super.key, this.home, this.gateway});

  final Widget? home;

  /// Injectable transport for tests that need the real shell wiring rather
  /// than a hand-built [home].
  final TransportGateway? gateway;

  @override
  State<RobotStudioApp> createState() => _RobotStudioAppState();
}

class _RobotStudioAppState extends State<RobotStudioApp>
    with WidgetsBindingObserver {
  /// Set by [AppShell] once settings load; drives [MaterialApp.themeMode].
  final _themePreference = ValueNotifier<String>('dark');

  /// Curated accent id (`teal` default); rebuilds light/dark [AppPalette]s.
  final _accentPreference = ValueNotifier<String>('teal');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // macOS often never delivers `detached` on window-close quit; native
    // AppDelegate also kills via the pid file. Do not stop on `hidden` —
    // minimize must keep the backend alive.
    if (state == AppLifecycleState.detached) {
      unawaited(BackendHost.instance?.stop() ?? Future<void>.value());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackendHost.instance?.stopSync();
    _themePreference.dispose();
    _accentPreference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _themePreference,
      builder: (context, preference, _) {
        return ValueListenableBuilder<String>(
          valueListenable: _accentPreference,
          builder: (context, accent, _) {
            final accentPref = AppAccentPreference.fromApi(accent);
            return MaterialApp(
              title: 'Robot Studio',
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(
                AppPalette.forAccent(
                  accentPref,
                  brightness: Brightness.light,
                ),
              ),
              darkTheme: buildAppTheme(
                AppPalette.forAccent(
                  accentPref,
                  brightness: Brightness.dark,
                ),
              ),
              themeMode: appThemeModeFor(preference),
              home:
                  widget.home ??
                  AppShell(
                    gateway: widget.gateway,
                    themePreference: _themePreference,
                    accentPreference: _accentPreference,
                  ),
            );
          },
        );
      },
    );
  }
}
