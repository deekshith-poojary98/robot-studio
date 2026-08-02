import 'package:flutter/foundation.dart';

/// Copy for the “no host Python” case (create env / first-run toast / errors).
///
/// Robot Studio’s backend may be running, but project environments still need a
/// usable system (or user-installed) Python 3 interpreter for `venv` + Robot.
abstract final class PythonInstallGuidance {
  static bool get _mac =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static const summary = 'No Python interpreter was found on this machine.';

  static const toastTitle = 'Python is not installed';

  static const toastMessage =
      'Robot Studio needs Python 3 to create environments and run Robot '
      'Framework tests. Install Python, then create an environment.';

  static String get shortRecovery {
    if (_mac) {
      return 'Install Python 3 (brew install python, or python.org), restart '
          'Robot Studio, then create an environment.';
    }
    if (_windows) {
      return 'Install Python 3 from python.org or the Microsoft Store '
          '(enable “Add to PATH”), restart Robot Studio, then create an '
          'environment.';
    }
    return 'Install Python 3 with your package manager (e.g. sudo apt install '
        'python3), restart Robot Studio, then create an environment.';
  }

  /// Longer body for a guidance dialog.
  static String get detailedInstructions {
    if (_mac) {
      return 'Robot Studio could not find Python 3 on this Mac.\n\n'
          'Install it, then restart Robot Studio:\n\n'
          '• Homebrew: brew install python\n'
          '• Or download the installer from https://www.python.org/downloads/\n\n'
          'When Python is available, create an environment from the toast or '
          'Manage Environments.';
    }
    if (_windows) {
      return 'Robot Studio could not find Python 3 on this PC.\n\n'
          'Install it, then restart Robot Studio:\n\n'
          '• Download from https://www.python.org/downloads/ '
          '(check “Add python.exe to PATH”)\n'
          '• Or install “Python 3” from the Microsoft Store\n\n'
          'When Python is available, create an environment from the toast or '
          'Manage Environments.';
    }
    return 'Robot Studio could not find Python 3 on this machine.\n\n'
        'Install it, then restart Robot Studio:\n\n'
        '• Debian/Ubuntu: sudo apt install python3 python3-venv\n'
        '• Fedora: sudo dnf install python3\n'
        '• Or download from https://www.python.org/downloads/\n\n'
        'When Python is available, create an environment from the toast or '
        'Manage Environments.';
  }

  /// Compact banner inside Create Environment when discovery returns nothing.
  static String get createDialogBanner {
    if (_mac) {
      return 'No Python found. Install with brew install python (or from '
          'python.org), tap Refresh, or Browse to an interpreter.';
    }
    if (_windows) {
      return 'No Python found. Install from python.org or the Microsoft Store '
          '(Add to PATH), tap Refresh, or Browse to python.exe.';
    }
    return 'No Python found. Install python3 (and python3-venv), tap Refresh, '
        'or Browse to an interpreter.';
  }

  /// True when [error] looks like the empty-interpreter discovery failure.
  static bool matchesError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('no python interpreter') ||
        text.contains('no python found') ||
        text.contains('python was not found') ||
        (text.contains('python') &&
            text.contains('not found') &&
            text.contains('machine'));
  }
}
