import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/preferences/editor_font_families.dart';

void main() {
  test('curated list is exactly ten IDE monospace faces', () {
    expect(kEditorFontFamilies, hasLength(10));
    expect(kEditorFontFamilies.first, 'Menlo');
    expect(kEditorFontFamilies.toSet(), hasLength(10));
  });

  test('choices keep a legacy custom value at the top', () {
    final choices = editorFontFamilyChoices('Comic Sans MS');
    expect(choices.first, 'Comic Sans MS');
    expect(choices.skip(1), kEditorFontFamilies);
  });

  test('choices stay curated when the current value is already listed', () {
    expect(editorFontFamilyChoices('Fira Code'), kEditorFontFamilies);
    expect(editorFontFamilyChoices(''), kEditorFontFamilies);
  });
}
