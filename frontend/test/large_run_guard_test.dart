import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/settings_info.dart';
import 'package:robot_studio/presentation/shell/large_run_guard.dart';

void main() {
  group('LargeRunGuard', () {
    test('default threshold matches ExecutionSettings default', () {
      expect(
        LargeRunGuard.defaultThreshold,
        const ExecutionSettings().largeRunThreshold,
      );
      expect(LargeRunGuard.defaultThreshold, 100);
    });

    test('does not confirm at or below default threshold', () {
      expect(
        LargeRunGuard.needsConfirmation(
          count: 100,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: 50,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: 0,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isFalse,
      );
    });

    test('confirms above default threshold', () {
      expect(
        LargeRunGuard.needsConfirmation(
          count: 101,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isTrue,
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: 1582,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isTrue,
      );
    });

    test('honors a custom lower threshold', () {
      const threshold = 25;
      expect(
        LargeRunGuard.needsConfirmation(count: 25, threshold: threshold),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(count: 26, threshold: threshold),
        isTrue,
      );
    });

    test('honors a custom higher threshold', () {
      const threshold = 500;
      expect(
        LargeRunGuard.needsConfirmation(count: 100, threshold: threshold),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(count: 500, threshold: threshold),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(count: 501, threshold: threshold),
        isTrue,
      );
    });

    test('wildcard tags always require confirmation', () {
      expect(
        LargeRunGuard.needsConfirmation(
          count: 1,
          threshold: 1000,
          tag: 'smoke*',
        ),
        isTrue,
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: 1,
          threshold: 1000,
          tag: 'a OR b',
        ),
        isTrue,
      );
      expect(LargeRunGuard.isWildcardTag('a AND b'), isTrue);
      expect(LargeRunGuard.isWildcardTag('a NOT b'), isTrue);
      expect(LargeRunGuard.isWildcardTag('smoke?'), isTrue);
      expect(
        LargeRunGuard.isWildcardTag('regression'),
        isFalse,
      );
    });

    test('boolean operators are space-delimited, not substrings', () {
      expect(LargeRunGuard.isWildcardTag('important'), isFalse);
      expect(LargeRunGuard.isWildcardTag('report'), isFalse);
      expect(LargeRunGuard.isWildcardTag('work'), isFalse);
      expect(LargeRunGuard.isWildcardTag('notation'), isFalse);
    });

    test('unknown count is not treated as a small run', () {
      expect(
        LargeRunGuard.needsConfirmation(
          count: null,
          threshold: LargeRunGuard.defaultThreshold,
        ),
        isFalse,
        reason: 'defer to backend 409 instead of assuming zero tests',
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: null,
          threshold: 1000,
          tag: 'smoke*',
        ),
        isTrue,
        reason: 'wildcard still pre-confirms when the estimate is missing',
      );
    });

    test('ExecutionSettings fromJson preserves custom large_run_threshold', () {
      final settings = ExecutionSettings.fromJson({
        'large_run_threshold': 42,
      });
      expect(settings.largeRunThreshold, 42);
      expect(
        LargeRunGuard.needsConfirmation(
          count: 42,
          threshold: settings.largeRunThreshold,
        ),
        isFalse,
      );
      expect(
        LargeRunGuard.needsConfirmation(
          count: 43,
          threshold: settings.largeRunThreshold,
        ),
        isTrue,
      );
    });
  });
}
