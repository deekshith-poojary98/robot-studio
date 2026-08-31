import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/language/robot_library_edit.dart';

void main() {
  test('inserts Library after existing imports in Settings', () {
    const content =
        '*** Settings ***\nLibrary    Collections\n\n*** Test Cases ***\nDemo\n    Log    hi\n';
    final updated = insertLibraryImport(content, 'RequestsLibrary');
    expect(updated, isNotNull);
    expect(updated, contains('Library    RequestsLibrary'));
    expect(
      updated!.indexOf('Library    RequestsLibrary'),
      lessThan(updated.indexOf('*** Test Cases ***')),
    );
    expect(insertLibraryImport(updated, 'RequestsLibrary'), isNull);
  });

  test('creates a Settings section when the file has none', () {
    const content = '*** Test Cases ***\nDemo\n    Log    hi\n';
    final updated = insertLibraryImport(content, 'RequestsLibrary');
    expect(updated, startsWith('*** Settings ***'));
    expect(updated, contains('Library    RequestsLibrary'));
    expect(updated, contains('*** Test Cases ***'));
  });
}
