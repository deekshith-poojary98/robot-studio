import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/backend_host.dart';

void main() {
  test('resolveSidecarPath finds MacOS sibling binary', () {
    final dir = Directory.systemTemp.createTempSync('rs-sidecar-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fakeApp = File('${dir.path}/RobotStudio');
    fakeApp.writeAsStringSync('');
    final sidecar = File('${dir.path}/robot-studio-backend');
    sidecar.writeAsStringSync('');

    final found = BackendHost.resolveSidecarPath(
      resolvedExecutable: fakeApp.path,
    );
    expect(found, sidecar.path);
  });

  test(
    'resolveSidecarPath finds Resources/backend on macOS layout',
    () {
      final root = Directory.systemTemp.createTempSync('rs-app-');
      addTearDown(() => root.deleteSync(recursive: true));
      final macos = Directory('${root.path}/Contents/MacOS')
        ..createSync(recursive: true);
      final backend = Directory('${root.path}/Contents/Resources/backend')
        ..createSync(recursive: true);
      File('${macos.path}/RobotStudio').writeAsStringSync('');
      File('${backend.path}/robot-studio-backend').writeAsStringSync('');

      final found = BackendHost.resolveSidecarPath(
        resolvedExecutable: '${macos.path}/RobotStudio',
      );
      expect(found, isNotNull);
      expect(File(found!).existsSync(), isTrue);
      expect(found, endsWith('robot-studio-backend'));
    },
    skip: !Platform.isMacOS ? 'macOS Resources layout only' : false,
  );

  test('resolveSidecarPath returns null when missing', () {
    final dir = Directory.systemTemp.createTempSync('rs-empty-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fakeApp = File('${dir.path}/RobotStudio.exe')..writeAsStringSync('');
    expect(
      BackendHost.resolveSidecarPath(resolvedExecutable: fakeApp.path),
      isNull,
    );
  });

  test('pid file write/read/clear round-trips', () {
    final dir = Directory.systemTemp.createTempSync('rs-pid-');
    addTearDown(() => dir.deleteSync(recursive: true));
    BackendHost.writePidFile(4242, dataDir: dir);
    expect(BackendHost.readPidFile(dataDir: dir), 4242);
    BackendHost.clearPidFile(dataDir: dir);
    expect(BackendHost.readPidFile(dataDir: dir), isNull);
  });
}
