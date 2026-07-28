import 'package:flutter/painting.dart';
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

  test('Robot theme uses VS Code Dark+ token colors', () {
    final theme = codeThemeForPath('/ws/a.robot')!.theme;
    expect(theme['section']?.color, const Color(0xFF9CDCFE));
    expect(theme['keyword']?.color, const Color(0xFFC586C0));
    expect(theme['built_in']?.color, const Color(0xFF4EC9B0));
    expect(theme['variable']?.color, const Color(0xFF9CDCFE));
    expect(theme['template-variable']?.color, const Color(0xFF9CDCFE));
    expect(theme['title']?.color, const Color(0xFFDCDCAA));
    expect(theme['attr']?.color, const Color(0xFFDCDCAA));
  });
}
