import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/preferences/editor_font_families.dart';

void main() {
  test('default editor face is Menlo', () {
    expect(kDefaultEditorFontFamily, 'Menlo');
  });

  test('choices list the OS catalog with the default first', () {
    expect(
      editorFontFamilyChoices(
        'Fira Code',
        installed: const ['Fira Code', 'AAA Mono', 'Menlo'],
      ),
      ['Menlo', 'AAA Mono', 'Fira Code'],
    );
  });

  test('choices keep a legacy custom value at the top', () {
    expect(
      editorFontFamilyChoices(
        'Comic Sans MS',
        installed: const ['Menlo', 'Fira Code'],
      ),
      ['Comic Sans MS', 'Menlo', 'Fira Code'],
    );
  });

  test('empty catalog still offers the current or default face', () {
    expect(editorFontFamilyChoices('', installed: const []), [
      kDefaultEditorFontFamily,
    ]);
    expect(editorFontFamilyChoices('Fira Code', installed: const []), [
      'Fira Code',
    ]);
  });

  test('fallback stack skips the selected family', () {
    expect(editorFontFamilyFallback('Menlo'), [
      'Consolas',
      'Courier New',
      'monospace',
    ]);
    expect(editorFontFamilyFallback('Consolas').first, 'Menlo');
  });
}
