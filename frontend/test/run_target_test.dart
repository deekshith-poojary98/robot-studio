import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/execution/run_target.dart';

void main() {
  group('isRunnableSuitePath', () {
    test('accepts .robot only', () {
      expect(isRunnableSuitePath('tests/login.robot'), isTrue);
      expect(isRunnableSuitePath(r'C:\suite.ROBOT'), isTrue);
      expect(isRunnableSuitePath('keywords/helpers.resource'), isFalse);
      expect(isRunnableSuitePath('notes.txt'), isFalse);
      expect(isRunnableSuitePath(null), isFalse);
      expect(isRunnableSuitePath('  '), isFalse);
    });
  });

  group('resolveRunTargetPath', () {
    test('uses focused .robot suite', () {
      expect(
        resolveRunTargetPath(
          activeEditorPath: 'tests/login.robot',
          stickySuitePath: 'tests/other.robot',
        ),
        'tests/login.robot',
      );
    });

    test('refuses sticky suite while non-robot editor is focused', () {
      expect(
        resolveRunTargetPath(
          activeEditorPath: 'notes.txt',
          stickySuitePath: 'tests/login.robot',
        ),
        isNull,
      );
      expect(
        resolveRunTargetPath(
          activeEditorPath: 'keywords/helpers.resource',
          stickySuitePath: 'tests/login.robot',
        ),
        isNull,
      );
    });

    test('allows sticky suite only when no editor is focused', () {
      expect(
        resolveRunTargetPath(
          activeEditorPath: null,
          stickySuitePath: 'tests/login.robot',
        ),
        'tests/login.robot',
      );
      expect(
        resolveRunTargetPath(
          activeEditorPath: '',
          stickySuitePath: 'tests/login.robot',
        ),
        'tests/login.robot',
      );
    });

    test('returns null when sticky is not runnable', () {
      expect(
        resolveRunTargetPath(
          activeEditorPath: null,
          stickySuitePath: 'helpers.resource',
        ),
        isNull,
      );
    });
  });
}
