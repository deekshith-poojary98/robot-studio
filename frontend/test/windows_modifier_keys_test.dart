import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/presentation/editor/windows_modifier_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('windowsControlPressed is false off Windows', () {
    // On macOS/Linux CI this must not throw and must report false.
    expect(windowsControlPressed(), isFalse);
  });

  test('isGoToDefinitionModifierPressed does not throw', () {
    expect(isGoToDefinitionModifierPressed(), isA<bool>());
  });

  test('isGoToDefinitionPointerButtons accepts primary, secondary, and remapped masks', () {
    expect(isGoToDefinitionPointerButtons(kPrimaryMouseButton), isTrue);
    expect(isGoToDefinitionPointerButtons(kSecondaryMouseButton), isTrue);
    expect(
      isGoToDefinitionPointerButtons(
        kPrimaryMouseButton | kSecondaryMouseButton,
      ),
      isTrue,
    );
    expect(isGoToDefinitionPointerButtons(0), isTrue);
    expect(isGoToDefinitionPointerButtons(kMiddleMouseButton), isFalse);
  });
}
