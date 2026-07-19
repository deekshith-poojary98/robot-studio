import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/shell/app_shell.dart';

void main() {
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
