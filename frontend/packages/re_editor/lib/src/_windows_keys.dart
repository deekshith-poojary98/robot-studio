part of re_editor;

/// VK_CONTROL / VK_LCONTROL / VK_RCONTROL
const int _vkControl = 0x11;
const int _vkLControl = 0xA2;
const int _vkRControl = 0xA3;

typedef _KeyStateNative = Int32 Function(Int32 vKey);
typedef _KeyStateDart = int Function(int vKey);

_KeyStateDart? _getAsyncKeyState;
_KeyStateDart? _getKeyState;

void _ensureUser32() {
  if (_getAsyncKeyState != null || kIsWeb || !Platform.isWindows) return;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    _getAsyncKeyState =
        user32.lookupFunction<_KeyStateNative, _KeyStateDart>('GetAsyncKeyState');
    _getKeyState =
        user32.lookupFunction<_KeyStateNative, _KeyStateDart>('GetKeyState');
  } catch (_) {
    _getAsyncKeyState = null;
    _getKeyState = null;
  }
}

bool _winKeyDown(int vKey) {
  _ensureUser32();
  final asyncFn = _getAsyncKeyState;
  if (asyncFn != null && (asyncFn(vKey) & 0x8000) != 0) return true;
  final keyFn = _getKeyState;
  if (keyFn != null && (keyFn(vKey) & 0x8000) != 0) return true;
  return false;
}

bool _windowsControlPressed() {
  if (kIsWeb || !Platform.isWindows) return false;
  return _winKeyDown(_vkControl) ||
      _winKeyDown(_vkLControl) ||
      _winKeyDown(_vkRControl);
}

/// True when a go-to-definition mouse chord is active (Ctrl / ⌘).
///
/// On Windows, prefer Win32 key state so we stay in sync with the OS when
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
