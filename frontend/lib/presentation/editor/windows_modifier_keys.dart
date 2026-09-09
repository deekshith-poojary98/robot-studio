import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// VK_CONTROL / VK_LCONTROL / VK_RCONTROL
const int _vkControl = 0x11;
const int _vkLControl = 0xA2;
const int _vkRControl = 0xA3;

/// Win32 SHORT-returning key APIs are read as [Int32] so ARM64/x64 leftover
/// bits in the register cannot zero a 16-bit FFI decode.
typedef _KeyStateNative = Int32 Function(Int32 vKey);
typedef _KeyStateDart = int Function(int vKey);

_KeyStateDart? _getAsyncKeyState;
_KeyStateDart? _getKeyState;

void _ensureUser32() {
  if (_getAsyncKeyState != null || kIsWeb || !Platform.isWindows) return;
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    _getAsyncKeyState = user32.lookupFunction<_KeyStateNative, _KeyStateDart>(
      'GetAsyncKeyState',
    );
    _getKeyState = user32.lookupFunction<_KeyStateNative, _KeyStateDart>(
      'GetKeyState',
    );
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

/// Whether Ctrl is physically held, per the OS (not Flutter's key cache).
///
/// Flutter's [HardwareKeyboard] on Windows can desync after focus changes
/// (https://github.com/flutter/flutter/issues/102716): Ctrl may look stuck
/// (plain click → go to definition) or missing (Ctrl+click does nothing while
/// Ctrl+Shift+click still works once another key event refreshes state).
bool windowsControlPressed() {
  if (kIsWeb || !Platform.isWindows) return false;
  return _winKeyDown(_vkControl) ||
      _winKeyDown(_vkLControl) ||
      _winKeyDown(_vkRControl);
}

/// True when this pointer-down should be treated as a go-to-definition click
/// (primary, remapped-secondary, or a synthesized 0-button down).
bool isGoToDefinitionPointerButtons(int buttons) {
  if (buttons == 0) return true;
  return (buttons & (kPrimaryMouseButton | kSecondaryMouseButton)) != 0;
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
