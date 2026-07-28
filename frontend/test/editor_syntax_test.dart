import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/editor/editor_syntax.dart';

void main() {
  test('codeThemeForPath uses custom Robot grammar', () {
    final theme = codeThemeForPath('/ws/tests/login.robot');
    expect(theme, isNotNull);
    expect(theme!.languages.keys, ['robot']);

    final resource = codeThemeForPath('/ws/resources/shared.resource');
    expect(resource!.languages.keys, ['robot']);
  });

  test('codeThemeForPath maps common builtins', () {
    expect(codeThemeForPath('a.py')!.languages.keys, ['python']);
    expect(codeThemeForPath('a.json')!.languages.keys, ['json']);
    expect(codeThemeForPath('a.yaml')!.languages.keys, ['yaml']);
    expect(codeThemeForPath('a.yml')!.languages.keys, ['yaml']);
    expect(codeThemeForPath('a.md')!.languages.keys, ['markdown']);
    expect(codeThemeForPath('a.js')!.languages.keys, ['javascript']);
    expect(codeThemeForPath('a.ts')!.languages.keys, ['typescript']);
    expect(codeThemeForPath('a.dart')!.languages.keys, ['dart']);
    expect(codeThemeForPath('Dockerfile')!.languages.keys, ['dockerfile']);
  });

  test('codeThemeForPath returns null for unknown types', () {
    expect(codeThemeForPath('notes.txt'), isNull);
    expect(codeThemeForPath('binary.bin'), isNull);
  });
}
