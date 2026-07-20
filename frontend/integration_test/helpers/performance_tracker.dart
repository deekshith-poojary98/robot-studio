import 'dart:io';

import 'package:flutter/foundation.dart';

import 'integration_fixtures.dart';
import 'backend_process.dart';

/// Tracks operation durations and logs them for integration test analysis.
class PerformanceTracker {
  PerformanceTracker();

  final Map<String, List<Duration>> _samples = {};

  T measure<T>(String label, T Function() action) {
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      record(label, stopwatch.elapsed);
    }
  }

  Future<T> measureAsync<T>(
    String label,
    Future<T> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      record(label, stopwatch.elapsed);
    }
  }

  void record(String label, Duration duration) {
    _samples.putIfAbsent(label, () => []).add(duration);
    debugPrint('[perf] $label: ${duration.inMilliseconds}ms');
  }

  Map<String, Duration> averages() {
    return {
      for (final entry in _samples.entries)
        entry.key: Duration(
          milliseconds: entry.value
                  .map((item) => item.inMilliseconds)
                  .reduce((a, b) => a + b) ~/
              entry.value.length,
        ),
    };
  }

  void logSummary({String prefix = '[perf-summary]'}) {
    if (_samples.isEmpty) {
      debugPrint('$prefix no samples recorded');
      return;
    }
    for (final entry in _samples.entries) {
      final values = entry.value.map((item) => item.inMilliseconds).toList();
      final avg = values.reduce((a, b) => a + b) / values.length;
      debugPrint(
        '$prefix ${entry.key}: avg=${avg.toStringAsFixed(1)}ms '
        'samples=${values.length}',
      );
    }
  }
}

/// Creates isolated temporary directories for integration tests.
class TestResourceManager {
  TestResourceManager({required this.root});

  final Directory root;

  static Future<TestResourceManager> create() async {
    final root = await Directory.systemTemp.createTemp('robot_studio_it_');
    return TestResourceManager(root: root);
  }

  Directory workspaceLocation(String name) {
    final dir = Directory('${root.path}/locations/$name');
    dir.createSync(recursive: true);
    return dir;
  }

  Directory scratch(String name) {
    final dir = Directory('${root.path}/scratch/$name');
    dir.createSync(recursive: true);
    return dir;
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  void installTestPlugin(String workspacePath) {
    final target = Directory('$workspacePath/Plugins/integration-test-plugin');
    target.createSync(recursive: true);
    File('${target.path}/plugin.json').writeAsStringSync(
      IntegrationFixtures.testPluginJson.trim(),
    );
    File('${target.path}/plugin.py').writeAsStringSync(
      IntegrationFixtures.testPluginPy,
    );
  }
}

String defaultPythonInterpreter() {
  return Platform.environment['ROBOT_STUDIO_PYTHON'] ??
      Platform.environment['INTEGRATION_PYTHON'] ??
      (Platform.isWindows ? 'python' : 'python3');
}
