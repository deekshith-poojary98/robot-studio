import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/logging/app_logger.dart';

void main() {
  late Directory tempLogs;

  setUp(() async {
    tempLogs = await Directory.systemTemp.createTemp('rs-logs-');
    AppLogger.consoleEnabled = false;
    await AppLogger.closeFileLogging();
  });

  tearDown(() async {
    await AppLogger.closeFileLogging();
    if (tempLogs.existsSync()) {
      tempLogs.deleteSync(recursive: true);
    }
  });

  test('initFileLogging writes to a dated frontend file', () async {
    await AppLogger.initFileLogging(logsDir: tempLogs);
    AppLogger.info('hello file log', tag: 'Test');
    await AppLogger.closeFileLogging();

    final today = DateTime.now();
    final stamp =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final file = File('${tempLogs.path}/frontend-$stamp.log');
    expect(file.existsSync(), isTrue);
    final body = file.readAsStringSync();
    expect(body, contains('Frontend file logging'));
    expect(body, contains('hello file log'));
  });

  test('purgeOldLogs deletes files older than seven days', () async {
    final today = DateTime(2026, 8, 6);
    final sep = Platform.pathSeparator;
    final keep = File('${tempLogs.path}${sep}frontend-2026-08-06.log')
      ..writeAsStringSync('keep\n');
    final mid = File('${tempLogs.path}${sep}backend-2026-08-03.log')
      ..writeAsStringSync('mid\n');
    final stale = File('${tempLogs.path}${sep}frontend-2026-07-29.log')
      ..writeAsStringSync('stale\n');
    final notes = File('${tempLogs.path}${sep}notes.txt')
      ..writeAsStringSync('leave\n');

    final deleted = AppLogger.purgeOldLogs(
      tempLogs,
      retention: const Duration(days: 7),
      now: today,
    );

    expect(deleted.map((f) => f.path), contains(stale.path));
    expect(stale.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(mid.existsSync(), isTrue);
    expect(notes.existsSync(), isTrue);
  });

  test('file logging still works when console is disabled', () async {
    AppLogger.consoleEnabled = false;
    await AppLogger.initFileLogging(logsDir: tempLogs);
    AppLogger.error('release-build error', tag: 'Test');
    await AppLogger.closeFileLogging();

    final files = tempLogs
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
    expect(files, isNotEmpty);
    expect(files.first.readAsStringSync(), contains('release-build error'));
  });
}
