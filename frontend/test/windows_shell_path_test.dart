import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/panels/windows_shell_path.dart';

void main() {
  tearDown(() {
    debugWindowsPathReader = null;
  });

  test('splitWindowsPath drops empties and trims', () {
    expect(splitWindowsPath(r'C:\a;; C:\b ;'), [r'C:\a', r'C:\b']);
    expect(splitWindowsPath(null), isEmpty);
    expect(splitWindowsPath(''), isEmpty);
  });

  test(
    'mergeWindowsPathSegments keeps Machine-then-User order and dedupes',
    () {
      expect(
        mergeWindowsPathSegments([
          r'C:\Windows\System32',
          r'C:\Program Files\nodejs',
          r'c:\windows\system32',
          r'C:\Users\deeks\AppData\Roaming\npm',
        ]),
        [
          r'C:\Windows\System32',
          r'C:\Program Files\nodejs',
          r'C:\Users\deeks\AppData\Roaming\npm',
        ].join(';'),
      );
    },
  );

  test('readWindowsRegistryPath uses the test override', () {
    debugWindowsPathReader = () =>
        r'C:\Windows\System32;C:\Program Files\nodejs';
    expect(
      readWindowsRegistryPath(),
      r'C:\Windows\System32;C:\Program Files\nodejs',
    );
  });
}
