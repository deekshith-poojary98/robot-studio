import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/updates/update_info.dart';

void main() {
  group('compareAppVersions', () {
    test('detects newer minor', () {
      expect(
        compareAppVersions(
          aVersion: '1.2.0',
          aBuild: 1,
          bVersion: '1.1.0',
          bBuild: 99,
        ),
        greaterThan(0),
      );
    });

    test('same version prefers higher build', () {
      expect(
        compareAppVersions(
          aVersion: '1.1.0',
          aBuild: 7,
          bVersion: '1.1.0',
          bBuild: 6,
        ),
        greaterThan(0),
      );
    });

    test('equal versions return zero', () {
      expect(
        compareAppVersions(
          aVersion: 'v1.1.0',
          aBuild: 6,
          bVersion: '1.1.0',
          bBuild: 6,
        ),
        0,
      );
    });
  });

  group('isUpdateNewer', () {
    test('true when latest is ahead', () {
      expect(
        isUpdateNewer(
          latest: const UpdateInfo(
            version: '1.2.0',
            build: 1,
            tag: 'v1.2.0',
            channel: 'stable',
          ),
          currentVersion: '1.1.0',
          currentBuild: '6',
        ),
        isTrue,
      );
    });

    test('false when current matches latest', () {
      expect(
        isUpdateNewer(
          latest: const UpdateInfo(
            version: '1.1.0',
            build: 6,
            tag: 'v1.1.0',
            channel: 'stable',
          ),
          currentVersion: '1.1.0',
          currentBuild: '6',
        ),
        isFalse,
      );
    });
  });
}
