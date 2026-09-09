import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// VK_CONTROL / VK_LCONTROL / VK_RCONTROL
const int _vkControl = 0x11;
const int _vkLControl = 0xA2;
const int _vkRControl = 0xA3;

/// Hosts that remap Ctrl+left to a right-click often clear Ctrl in the same
/// message. Remember a recent physical Ctrl so the synthesized secondary
/// click still goes to definition.
const Duration _ctrlRemapWindow = Duration(milliseconds: 400);

/// Win32 SHORT-returning key APIs are read as [Int32] so ARM64/x64 leftover
/// bits in the register cannot zero a 16-bit FFI decode.
typedef _KeyStateNative = Int32 Function(Int32 vKey);
typedef _KeyStateDart = int Function(int vKey);

_KeyStateDart? _getAsyncKeyState;
_KeyStateDart? _getKeyState;
DateTime? _ctrlHeldAt;

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
bool windowsControlPressed() {
  if (kIsWeb || !Platform.isWindows) return false;
  return _winKeyDown(_vkControl) ||
      _winKeyDown(_vkLControl) ||
      _winKeyDown(_vkRControl);
}

/// Sample OS Ctrl (call from a timer / hover) so a remapped click still counts.
void pollWindowsControlForDefinition() {
  if (windowsControlPressed()) {
    _ctrlHeldAt = DateTime.now();
  }
}

bool windowsControlPressedOrRecentlyHeld() {
  if (windowsControlPressed()) return true;
  final at = _ctrlHeldAt;
  if (at == null) return false;
  return DateTime.now().difference(at) < _ctrlRemapWindow;
}

/// True when this pointer-down should be treated as a go-to-definition click
/// (primary, remapped-secondary, or a synthesized 0-button down).
bool isGoToDefinitionPointerButtons(int buttons) {
  if (buttons == 0) return true;
  return (buttons & (kPrimaryMouseButton | kSecondaryMouseButton)) != 0;
}

/// Whether this mouse-down is a go-to-definition chord.
///
/// Primary clicks require Ctrl to be down *now* so a later plain click does
/// not navigate. Secondary clicks also accept recently-held Ctrl because
/// Windows often remaps Ctrl+left to a right-click with Ctrl already cleared.
bool shouldGoToDefinitionOnPointerDown(int buttons) {
  if (!isGoToDefinitionPointerButtons(buttons)) return false;
  if (isGoToDefinitionModifierPressed()) return true;
  final secondary = (buttons & kSecondaryMouseButton) != 0;
  return secondary && windowsControlPressedOrRecentlyHeld();
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

@visibleForTesting
void debugMarkWindowsControlSeen([DateTime? at]) {
  _ctrlHeldAt = at ?? DateTime.now();
}

@visibleForTesting
void debugClearWindowsControlSeen() {
  _ctrlHeldAt = null;
}
