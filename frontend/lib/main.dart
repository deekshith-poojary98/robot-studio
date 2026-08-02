import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/backend_host.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  const RobotStudioApp({super.key, this.home});

  final Widget? home;

  @override
  State<RobotStudioApp> createState() => _RobotStudioAppState();
}

class _RobotStudioAppState extends State<RobotStudioApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      BackendHost.instance?.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robot Studio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: widget.home ?? const AppShell(),
    );
  }
}
