import 'package:flutter/foundation.dart';

/// Notifies [AppShell] to rebuild after controller state changes.
typedef ShellNotify = VoidCallback;

/// Returns whether the owning widget is still mounted.
typedef ShellMounted = bool Function();
