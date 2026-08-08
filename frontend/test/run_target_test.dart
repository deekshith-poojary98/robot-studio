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
        resolveRunTargetPath(activeEditorPath: 'tests/login.robot'),
        'tests/login.robot',
      );
    });

    test('returns null when non-robot editor is focused', () {
      expect(resolveRunTargetPath(activeEditorPath: 'notes.txt'), isNull);
      expect(
        resolveRunTargetPath(activeEditorPath: 'keywords/helpers.resource'),
        isNull,
      );
    });

    test('returns null when no editor is open', () {
      expect(resolveRunTargetPath(activeEditorPath: null), isNull);
      expect(resolveRunTargetPath(activeEditorPath: ''), isNull);
    });
  });
}
