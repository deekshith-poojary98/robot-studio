import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shell/app_shell.dart';

void main() {
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

  runApp(const RobotStudioApp());
}

class RobotStudioApp extends StatelessWidget {
  const RobotStudioApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Robot Studio',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home ?? const AppShell(),
    );
  }
}
