part of re_editor;

/// VK_CONTROL
const int _vkControl = 0x11;

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

_GetAsyncKeyStateDart? _getAsyncKeyState;

bool _windowsControlPressed() {
  if (kIsWeb || !Platform.isWindows) return false;
  try {
    _getAsyncKeyState ??= DynamicLibrary.open('user32.dll')
        .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
          'GetAsyncKeyState',
        );
    return (_getAsyncKeyState!(_vkControl) & 0x8000) != 0;
  } catch (_) {
    return false;
  }
}

/// True when a go-to-definition mouse chord is active (Ctrl / ⌘).
///
/// On Windows, prefer GetAsyncKeyState so we stay in sync with the OS when
/// Flutter's [HardwareKeyboard] cache is wrong.
bool _isDefinitionModifierPressed() {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return HardwareKeyboard.instance.isMetaPressed;
  }
  if (!kIsWeb && Platform.isWindows) {
    return _windowsControlPressed();
  }
  return HardwareKeyboard.instance.isControlPressed;
}
