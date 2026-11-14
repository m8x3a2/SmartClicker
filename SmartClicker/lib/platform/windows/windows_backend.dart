// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io' show Platform, exit;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../backend.dart';
import '../../core/vision/image.dart';
import '../keys.dart';
import 'ocr.dart';
import 'ocr.dart' as winocr show ocrLanguages;
import 'tray.dart';
import 'folder_dialog.dart';

part 'win32_bindings.dart';
part 'system_windows.dart';
part 'program_window.dart';
part 'key_hook.dart';
part 'startup_entry.dart';

class WindowsBackend with _SystemWindows, _ProgramWindow, _KeyHook, _StartupEntry implements PlatformBackend {
  @override
  String get name => 'windows';

  @override
  int get ownPid => _GetCurrentProcessId();

  @override
  String? pickFile(
      {required bool save, required String title, String defaultName = '', String ext = 'zip'}) {
    try {
      return super.pickFile(save: save, title: title, defaultName: defaultName, ext: ext);
    } finally {
      _adoptStrayWindows();
    }
  }

  @override
  ({int w, int h}) screenSize() =>
      (w: _GetSystemMetrics(0), h: _GetSystemMetrics(1));

  @override
  Pt cursorPos() {
    final p = calloc<Int32>(2);
    try {
      _GetCursorPos(p);
      return (x: p[0], y: p[1]);
    } finally {
      calloc.free(p);
    }
  }

  void _mouseInput(int dx, int dy, int data, int flags) {
    final buf = calloc<Uint8>(_inputSize);
    try {
      final d = ByteData.sublistView(buf.asTypedList(_inputSize));
      d.setUint32(0, 0, Endian.little); // INPUT_MOUSE
      d.setInt32(8, dx, Endian.little);
      d.setInt32(12, dy, Endian.little);
      d.setInt32(16, data, Endian.little);
      d.setUint32(20, flags, Endian.little);
      d.setUint64(32, _ownInputTag, Endian.little); // dwExtraInfo: see key_hook
      _SendInput(1, buf, _inputSize);
    } finally {
      calloc.free(buf);
    }
  }

  void _keyInput(int vk, int scan, int flags) {
    final buf = calloc<Uint8>(_inputSize);
    try {
      final d = ByteData.sublistView(buf.asTypedList(_inputSize));
      d.setUint32(0, 1, Endian.little); // INPUT_KEYBOARD
      d.setUint16(8, vk, Endian.little);
      d.setUint16(10, scan, Endian.little);
      d.setUint32(12, flags, Endian.little);
      d.setUint64(24, _ownInputTag, Endian.little); // dwExtraInfo: see key_hook
      _SendInput(1, buf, _inputSize);
    } finally {
      calloc.free(buf);
    }
  }

  @override
  void moveTo(int x, int y) {
    // Absolute move over the whole virtual desktop (works with several
    // monitors and is seen by games as real mouse movement).
    final vx = _GetSystemMetrics(76), vy = _GetSystemMetrics(77);
    final vw = _GetSystemMetrics(78), vh = _GetSystemMetrics(79);
    if (vw > 1 && vh > 1) {
      final nx = ((x - vx) * 65535 / (vw - 1)).round();
      final ny = ((y - vy) * 65535 / (vh - 1)).round();
      _mouseInput(nx, ny, 0, 0x0001 | 0x8000 | 0x4000);
    }
    final p = cursorPos();
    if (p.x != x || p.y != y) _SetCursorPos(x, y);
  }

  @override
  void mouseButton(String button, bool down) {
    final b = _mouseButtons[button];
    if (b == null) {
      throw ArgumentError('неизвестная кнопка мыши "$button" (left, right, middle)');
    }
    _mouseInput(0, 0, 0, down ? b.down : b.up);
  }

  @override
  void scroll(int amount, {bool horizontal = false}) {
    if (horizontal) {
      _mouseInput(0, 0, amount * 120, 0x1000);
    } else {
      _mouseInput(0, 0, -amount * 120, 0x0800);
    }
  }

  @override
  void keyEvent(String key, bool down) {
    final vk = vkByName[key.toLowerCase()];
    if (vk == null) throw ArgumentError('неизвестная клавиша "$key"');
    _vkEvent(vk, down);
  }

  @override
  void _vkEvent(int vk, bool down) {
    var flags = down ? 0 : 0x0002;
    if (extendedVks.contains(vk)) flags |= 0x0001;
    _keyInput(vk, _MapVirtualKeyW(vk, 0), flags);
  }

  @override
  void typeText(String text) {
    for (final unit in text.codeUnits) {
      if (unit == 0x0A) {
        _vkEvent(0x0D, true);
        _vkEvent(0x0D, false);
        continue;
      }
      if (unit == 0x0D) continue;
      _keyInput(0, unit, 0x0004); // KEYEVENTF_UNICODE
      _keyInput(0, unit, 0x0004 | 0x0002);
    }
  }

  @override
  int pixel(int x, int y) {
    final dc = _GetDC(0);
    try {
      final c = _GetPixel(dc, x, y);
      if (c == 0xFFFFFFFF) return 0;
      return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
    } finally {
      _ReleaseDC(0, dc);
    }
  }

  @override
  Uint8List capture(int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) return Uint8List(0);
    final screen = _GetDC(0);
    final mem = _CreateCompatibleDC(screen);
    final bmp = _CreateCompatibleBitmap(screen, w, h);
    final old = _SelectObject(mem, bmp);
    final bytes = w * h * 4;
    final buf = calloc<Uint8>(bytes);
    final bmi = calloc<Uint8>(64);
    try {
      _BitBlt(mem, 0, 0, w, h, screen, x, y, 0x00CC0020);
      _SelectObject(mem, old);
      final d = ByteData.sublistView(bmi.asTypedList(64));
      d.setUint32(0, 40, Endian.little);
      d.setInt32(4, w, Endian.little);
      d.setInt32(8, -h, Endian.little); // top-down rows
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      _GetDIBits(screen, bmp, 0, h, buf, bmi, 0);
      return Uint8List.fromList(buf.asTypedList(bytes));
    } finally {
      calloc.free(buf);
      calloc.free(bmi);
      _DeleteObject(bmp);
      _DeleteDC(mem);
      _ReleaseDC(0, screen);
    }
  }

  @override
  String readText(int x, int y, int w, int h, {String lang = '', int scale = 0}) {
    if (w <= 0 || h <= 0) return '';
    return ocrImage(capture(x, y, w, h), w, h, lang: lang, scale: scale);
  }

  @override
  String ocrImage(Uint8List bgra, int w, int h, {String lang = '', int scale = 0}) {
    if (w <= 0 || h <= 0) return '';
    // Small text is recognized far better when enlarged.
    var k = scale > 0 ? scale : (h < 60 ? 3 : (h < 400 ? 2 : 1));
    while (k > 1 && (w * k > 8000 || h * k > 8000)) {
      k--;
    }
    final img = upscale(Bitmap(w, h, bgra), k);
    return ocrBgra(img.bgra, img.w, img.h, lang: lang);
  }

  int _wheelHook = 0;
  NativeCallable<_HookProc>? _wheelProc;

  @override
  bool watchWheel(void Function(int delta, bool horizontal, int x, int y) onWheel) {
    unwatchWheel();
    // A low-level hook is served by the message loop of the thread that set
    // it. That is the thread of our window; from any other thread the hook
    // would never be answered and the mouse of the whole system would lag.
    final hwnd = _findMainWindow();
    if (hwnd == 0 ||
        _GetWindowThreadProcessId(hwnd, nullptr) != _GetCurrentThreadId()) {
      return false;
    }
    _wheelSink = onWheel;
    final proc = NativeCallable<_HookProc>.isolateLocal(_mouseHook,
        exceptionalReturn: 0);
    _wheelHook = _SetWindowsHookExW(
        14, proc.nativeFunction, _GetModuleHandleW(nullptr), 0); // WH_MOUSE_LL
    if (_wheelHook == 0) {
      proc.close();
      _wheelSink = null;
      return false;
    }
    _wheelProc = proc;
    return true;
  }

  @override
  void unwatchWheel() {
    if (_wheelHook != 0) _UnhookWindowsHookEx(_wheelHook);
    _wheelHook = 0;
    _wheelProc?.close();
    _wheelProc = null;
    _wheelSink = null;
  }

  @override
  bool isVkDown(int vk) => _physicallyDown(vk) || _heldBack(vk);

  @override
  bool _physicallyDown(int vk) => (_GetAsyncKeyState(vk) & 0x8000) != 0;

  /// Diagnostics for the keyboard-layout detection.
  String layoutDebug() {
    final t = inputThreads();
    String h(int v) => (v & 0xFFFFFFFF).toRadixString(16);
    return 'fgThread=${t.foreground} hkl=${h(_GetKeyboardLayout(t.foreground))} '
        'focusThread=${t.focus} hkl=${h(_GetKeyboardLayout(t.focus))} '
        'own hkl=${h(_GetKeyboardLayout(0))}';
  }

  @override
  String? charForVk(int vk, {required bool shift}) {
    final layout = _GetKeyboardLayout(inputThreads().focus);
    final state = calloc<Uint8>(256);
    final buf = calloc<Uint16>(8);
    try {
      if (shift) state[0x10] = 0x80;
      if ((_GetKeyState(0x14) & 1) != 0) state[0x14] = 1; // Caps Lock
      // Flag 4: do not disturb the system's own keyboard state.
      final n = _ToUnicodeEx(
          vk, _MapVirtualKeyW(vk, 0), state, buf, 8, 4, layout);
      if (n != 1 || buf[0] < 0x20 || buf[0] == 0x7F) return null;
      return String.fromCharCode(buf[0]);
    } finally {
      calloc.free(state);
      calloc.free(buf);
    }
  }

  @override
  Never endProcess() {
    _TerminateProcess(-1, 0); // -1: this process
    exit(0); // not reached
  }

  @override
  void releaseAll() {
    for (final b in _mouseButtons.entries) {
      if (isVkDown(b.value.vk)) mouseButton(b.key, false);
    }
    // Keys eaten by the key hook never reached anybody: nothing to release.
    for (var vk = 8; vk < 0xFF; vk++) {
      if (_physicallyDown(vk)) _vkEvent(vk, false);
    }
  }
}
