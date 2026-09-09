import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// VK_CONTROL — either Ctrl key down (high bit set while pressed).
const int _vkControl = 0x11;

typedef _GetAsyncKeyStateNative = Int16 Function(Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

_GetAsyncKeyStateDart? _getAsyncKeyState;

_GetAsyncKeyStateDart? get _asyncKeyState {
  if (_getAsyncKeyState != null) return _getAsyncKeyState;
  if (kIsWeb || !Platform.isWindows) return null;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    _getAsyncKeyState = user32
        .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
          'GetAsyncKeyState',
        );
  } catch (_) {
    _getAsyncKeyState = null;
  }
  return _getAsyncKeyState;
}

/// Whether Ctrl is physically held, per the OS (not Flutter's key cache).
///
/// Flutter's [HardwareKeyboard] on Windows can desync after focus changes
/// (https://github.com/flutter/flutter/issues/102716): Ctrl may look stuck
/// (plain click → go to definition) or missing (Ctrl+click does nothing while
/// Ctrl+Shift+click still works once another key event refreshes state).
bool windowsControlPressed() {
  final fn = _asyncKeyState;
  if (fn == null) return false;
  return (fn(_vkControl) & 0x8000) != 0;
}

/// Modifier for go-to-definition click (⌘ on macOS, Ctrl elsewhere).
///
/// Never uses the Windows key (meta) on Windows — that caused plain clicks to
/// navigate when Win was sticky.
bool isGoToDefinitionModifierPressed() {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return HardwareKeyboard.instance.isMetaPressed;
  }
  if (!kIsWeb && Platform.isWindows) {
    return windowsControlPressed();
  }
  return HardwareKeyboard.instance.isControlPressed;
}
