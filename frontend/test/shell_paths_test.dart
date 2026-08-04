import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/shell/shell_paths.dart';

void main() {
  group('sameFsPath', () {
    test('matches equal and trailing-slash variants', () {
      expect(sameFsPath('/Users/me/Demo', '/Users/me/Demo'), isTrue);
      expect(sameFsPath('/Users/me/Demo/', '/Users/me/Demo'), isTrue);
      expect(sameFsPath(r'C:\proj\A', r'C:\proj\A'), isTrue);
      expect(sameFsPath(r'C:\proj\A', 'C:/proj/A'), isTrue);
    });

    test('rejects different roots (standalone vs nested)', () {
      expect(
        sameFsPath('/Users/me/WS', '/Users/me/WS/Projects/Demo'),
        isFalse,
      );
      expect(sameFsPath(null, '/tmp/a'), isFalse);
      expect(sameFsPath('/tmp/a', null), isFalse);
    });
  });
}
