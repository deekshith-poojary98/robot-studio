import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/editor/editor_syntax.dart';

void main() {
  const dark = AppPalette.dark;
  const light = AppPalette.light;

  test('codeThemeForPath uses custom Robot grammar', () {
    final theme = codeThemeForPath('/ws/tests/login.robot', dark);
    expect(theme, isNotNull);
    expect(theme!.languages.keys, ['robot']);

    final resource = codeThemeForPath('/ws/resources/shared.resource', dark);
    expect(resource!.languages.keys, ['robot']);
  });

  test('codeThemeForPath maps common builtins', () {
    expect(codeThemeForPath('a.py', dark)!.languages.keys, ['python']);
    expect(codeThemeForPath('a.json', dark)!.languages.keys, ['json']);
    expect(codeThemeForPath('a.yaml', dark)!.languages.keys, ['yaml']);
    expect(codeThemeForPath('a.yml', dark)!.languages.keys, ['yaml']);
    expect(codeThemeForPath('a.md', dark)!.languages.keys, ['markdown']);
    expect(codeThemeForPath('a.js', dark)!.languages.keys, ['javascript']);
    expect(codeThemeForPath('a.ts', dark)!.languages.keys, ['typescript']);
    expect(codeThemeForPath('a.dart', dark)!.languages.keys, ['dart']);
    expect(codeThemeForPath('Dockerfile', dark)!.languages.keys, [
      'dockerfile',
    ]);
  });

  test('codeThemeForPath returns null for unknown types', () {
    expect(codeThemeForPath('notes.txt', dark), isNull);
    expect(codeThemeForPath('binary.bin', dark), isNull);
  });

  test('Robot theme uses VS Code Dark+ token colors', () {
    final theme = codeThemeForPath('/ws/a.robot', dark)!.theme;
    expect(theme['section']?.color, const Color(0xFF9CDCFE));
    expect(theme['keyword']?.color, const Color(0xFFC586C0));
    expect(theme['built_in']?.color, const Color(0xFF4EC9B0));
    expect(theme['variable']?.color, const Color(0xFF9CDCFE));
    expect(theme['template-variable']?.color, const Color(0xFF9CDCFE));
    expect(theme['title']?.color, const Color(0xFFDCDCAA));
    expect(theme['attr']?.color, const Color(0xFFDCDCAA));
  });

  test('light palette swaps in VS Code Light+ token colors', () {
    final theme = codeThemeForPath('/ws/a.robot', light)!.theme;
    expect(theme['section']?.color, const Color(0xFF001080));
    expect(theme['keyword']?.color, const Color(0xFFAF00DB));
    expect(theme['built_in']?.color, const Color(0xFF267F99));
    expect(theme['title']?.color, const Color(0xFF795E26));
    expect(theme['string']?.color, const Color(0xFFA31515));
    expect(theme['number']?.color, const Color(0xFF098658));
  });

  test('builtin-grammar tokens follow the palette', () {
    // `root`, `string`, `keyword` and friends are deliberately overridden for
    // every language by the Robot token map, so assert on tokens it leaves
    // alone to prove the palette reaches the shared theme.
    final darkTheme = codeThemeForPath('a.py', dark)!.theme;
    final lightTheme = codeThemeForPath('a.py', light)!.theme;
    expect(darkTheme['literal']?.color, dark.accent);
    expect(lightTheme['literal']?.color, light.accent);
    expect(darkTheme['name']?.color, dark.error);
    expect(lightTheme['name']?.color, light.error);
    expect(darkTheme['type']?.color, dark.warning);
    expect(lightTheme['type']?.color, light.warning);
  });

  test('highlightSourceForPath tokens Robot section headers', () {
    final span = highlightSourceForPath(
      '*** Variables ***\n\${URL}    https://example.com\n',
      'tests/login.robot',
      dark,
    );
    expect(_collectColors(span), contains(const Color(0xFF9CDCFE)));
  });

  test('highlightLinesForPath preserves row count across empty sides', () {
    final spans = highlightLinesForPath(
      const ['Library    Browser', '', '*** Variables ***'],
      'tests/login.robot',
      dark,
    );
    expect(spans, hasLength(3));
    expect(_spanText(spans[0]), 'Library    Browser');
    expect(_spanText(spans[1]), '');
    expect(_spanText(spans[2]), '*** Variables ***');
  });

  test('splitTextSpanByNewlines keeps styles across line breaks', () {
    const root = TextSpan(
      children: [
        TextSpan(
          text: 'aaa',
          style: TextStyle(color: Color(0xFF111111)),
        ),
        TextSpan(
          text: '\nbbb',
          style: TextStyle(color: Color(0xFF222222)),
        ),
      ],
    );
    final lines = splitTextSpanByNewlines(root, expectedLineCount: 2);
    expect(lines, hasLength(2));
    expect(_spanText(lines[0]), 'aaa');
    expect(_spanText(lines[1]), 'bbb');
  });
}

String _spanText(TextSpan span) {
  final buffer = StringBuffer();
  void walk(InlineSpan node) {
    if (node is! TextSpan) return;
    if (node.text != null) buffer.write(node.text);
    final children = node.children;
    if (children == null) return;
    for (final child in children) {
      walk(child);
    }
  }

  walk(span);
  return buffer.toString();
}

Set<Color> _collectColors(TextSpan span) {
  final colors = <Color>{};
  void walk(InlineSpan node) {
    final color = node.style?.color;
    if (color != null) colors.add(color);
    if (node is! TextSpan) return;
    final children = node.children;
    if (children == null) return;
    for (final child in children) {
      walk(child);
    }
  }

  walk(span);
  return colors;
}
