// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');

typedef _WndProc = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);

final _RegisterClassExW = _user32.lookupFunction<Uint16 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('RegisterClassExW');
final _UnregisterClassW = _user32.lookupFunction<Int32 Function(Pointer<Utf16>, IntPtr),
    int Function(Pointer<Utf16>, int)>('UnregisterClassW');
final _CreateWindowExW = _user32.lookupFunction<
    IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32,
        Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer<Void>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int,
        int, int, int, Pointer<Void>)>('CreateWindowExW');
final _DestroyWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');
final _DefWindowProcW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('DefWindowProcW');
final _RegisterWindowMessageW = _user32.lookupFunction<
    Uint32 Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>('RegisterWindowMessageW');
final _GetModuleHandleW = _kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
    int Function(Pointer<Utf16>)>('GetModuleHandleW');
final _LoadImageW = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Uint32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int)>('LoadImageW');
final _GetSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');
final _Shell_NotifyIconW = _shell32.lookupFunction<Int32 Function(Uint32, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('Shell_NotifyIconW');
final _CreatePopupMenu =
    _user32.lookupFunction<IntPtr Function(), int Function()>('CreatePopupMenu');
final _AppendMenuW = _user32.lookupFunction<
    Int32 Function(IntPtr, Uint32, IntPtr, Pointer<Utf16>),
    int Function(int, int, int, Pointer<Utf16>)>('AppendMenuW');
final _SetMenuDefaultItem = _user32.lookupFunction<Int32 Function(IntPtr, Uint32, Uint32),
    int Function(int, int, int)>('SetMenuDefaultItem');
final _TrackPopupMenu = _user32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Int32, Int32, Int32, IntPtr, Pointer<Void>),
    int Function(int, int, int, int, int, int, Pointer<Void>)>('TrackPopupMenu');
final _DestroyMenu = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu');
final _GetCursorPos = _user32.lookupFunction<Int32 Function(Pointer<Int32>),
    int Function(Pointer<Int32>)>('GetCursorPos');
final _SetForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final _PostMessageW = _user32.lookupFunction<
    Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('PostMessageW');

/// An icon in the notification area (system tray) with a menu and balloon
/// messages. Lives in the UI isolate: its hidden window gets its messages
/// from the runner's message loop on this same thread.
class WinTray {
  static const _callbackMsg = 0x8001; // WM_APP + 1
  static const _nidSize = 976; // NOTIFYICONDATAW, x64

  final void Function(String event) onEvent;

  /// The main window. The tray window is owned by it: an owned window is
  /// not counted as a second top-level window (Flutter handles the close
  /// button only for the last one).
  final int owner;
  WinTray(this.onEvent, {this.owner = 0});

  int _hwnd = 0;
  int _icon = 0;
  int _taskbarCreated = 0;
  bool _added = false;
  String _tip = '';
  NativeCallable<_WndProc>? _proc;
  Pointer<Utf16>? _className;

  bool get shown => _added;

  bool _ensureWindow() {
    if (_hwnd != 0) return true;
    final proc = NativeCallable<_WndProc>.isolateLocal(_wndProc, exceptionalReturn: 0);
    final inst = _GetModuleHandleW(nullptr);
    final cls = 'SmartClickerTray'.toNativeUtf16();
    final wc = calloc<Uint8>(80);
    try {
      final d = ByteData.sublistView(wc.asTypedList(80));
      d.setUint32(0, 80, Endian.little); // cbSize
      d.setUint64(8, proc.nativeFunction.address, Endian.little);
      d.setUint64(24, inst, Endian.little);
      d.setUint64(64, cls.address, Endian.little);
      _RegisterClassExW(wc); // fails harmlessly if registered before
      final empty = ''.toNativeUtf16();
      // A plain hidden popup (not message-only): the tray menu needs a
      // window that can be put in front.
      _hwnd = _CreateWindowExW(0, cls, empty, 0x80000000, 0, 0, 0, 0, owner, 0, inst, nullptr);
      calloc.free(empty);
    } finally {
      calloc.free(wc);
    }
    if (_hwnd == 0) {
      proc.close();
      calloc.free(cls);
      return false;
    }
    _proc = proc;
    _className = cls;
    final name = 'TaskbarCreated'.toNativeUtf16();
    _taskbarCreated = _RegisterWindowMessageW(name);
    calloc.free(name);
    // The application's own icon (IDI_APP_ICON = 101 in Runner.rc).
    _icon = _LoadImageW(inst, 101, 1, _GetSystemMetrics(49), _GetSystemMetrics(50), 0);
    if (_icon == 0) _icon = _LoadImageW(0, 32512, 1, 0, 0, 0x8000); // IDI_APPLICATION, shared
    return true;
  }

  int _wndProc(int hwnd, int msg, int wParam, int lParam) {
    if (msg == _callbackMsg) {
      final what = lParam & 0xFFFF;
      // Work is done after the callback returns (a menu runs its own loop).
      if (what == 0x0202) Timer.run(() => onEvent('open')); // WM_LBUTTONUP
      if (what == 0x0205) Timer.run(() => onEvent('menu')); // WM_RBUTTONUP
      return 0;
    }
    if (msg == _taskbarCreated && _taskbarCreated != 0 && _added) {
      // Explorer restarted: the icon has to be added again.
      _added = false;
      Timer.run(() => show(_tip));
      return 0;
    }
    return _DefWindowProcW(hwnd, msg, wParam, lParam);
  }

  Pointer<Uint8> _data(int flags) {
    final p = calloc<Uint8>(_nidSize);
    final d = ByteData.sublistView(p.asTypedList(_nidSize));
    d.setUint32(0, _nidSize, Endian.little);
    d.setUint64(8, _hwnd, Endian.little);
    d.setUint32(16, 1, Endian.little); // uID
    d.setUint32(20, flags, Endian.little);
    d.setUint32(24, _callbackMsg, Endian.little);
    d.setUint64(32, _icon, Endian.little);
    _writeText(p, 40, _tip, 127);
    return p;
  }

  static void _writeText(Pointer<Uint8> p, int offset, String s, int max) {
    final units = s.codeUnits;
    final n = units.length < max ? units.length : max;
    final w = (p + offset).cast<Uint16>();
    for (var i = 0; i < n; i++) {
      w[i] = units[i];
    }
    w[n] = 0;
  }

  /// Shows the icon (or updates its tooltip).
  bool show(String tip) {
    if (!_ensureWindow()) return false;
    _tip = tip;
    final p = _data(0x1 | 0x2 | 0x4); // MESSAGE | ICON | TIP
    try {
      if (_added) return _Shell_NotifyIconW(1, p) != 0; // NIM_MODIFY
      _added = _Shell_NotifyIconW(0, p) != 0; // NIM_ADD
      return _added;
    } finally {
      calloc.free(p);
    }
  }

  void setTip(String tip) {
    if (_added && tip != _tip) show(tip);
  }

  /// A balloon (on Windows 10/11 — a notification) next to the icon.
  void balloon(String title, String text) {
    if (!_added) return;
    final p = _data(0x10); // NIF_INFO
    try {
      _writeText(p, 304, text, 255);
      _writeText(p, 820, title, 63);
      ByteData.sublistView(p.asTypedList(_nidSize))
          .setUint32(948, 0x1 | 0x10, Endian.little); // NIIF_INFO | NIIF_NOSOUND
      _Shell_NotifyIconW(1, p);
    } finally {
      calloc.free(p);
    }
  }

  void hide() {
    if (!_added) return;
    final p = _data(0);
    _Shell_NotifyIconW(2, p); // NIM_DELETE
    calloc.free(p);
    _added = false;
  }

  /// Menu at the mouse pointer. Items: text, '' = separator, a leading '!'
  /// = greyed out; [bold] — the default item. Returns the chosen index or -1.
  int menu(List<String> items, {int bold = -1}) {
    if (!_ensureWindow()) return -1;
    final m = _CreatePopupMenu();
    final pt = calloc<Int32>(2);
    try {
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.isEmpty) {
          _AppendMenuW(m, 0x800, 0, nullptr); // MF_SEPARATOR
          continue;
        }
        final grey = it.startsWith('!');
        final text = (grey ? it.substring(1) : it).toNativeUtf16();
        _AppendMenuW(m, grey ? 0x1 : 0x0, i + 1, text); // MF_GRAYED / MF_STRING
        calloc.free(text);
      }
      if (bold >= 0) _SetMenuDefaultItem(m, bold + 1, 0);
      _GetCursorPos(pt);
      // Without this the menu would not close when clicking elsewhere.
      _SetForegroundWindow(_hwnd);
      final id = _TrackPopupMenu(
          m, 0x100 | 0x2 | 0x20, pt[0], pt[1], 0, _hwnd, nullptr); // RETURNCMD | RIGHTBUTTON | BOTTOMALIGN
      _PostMessageW(_hwnd, 0, 0, 0); // WM_NULL
      return id - 1;
    } finally {
      _DestroyMenu(m);
      calloc.free(pt);
    }
  }

  void dispose() {
    hide();
    if (_hwnd != 0) _DestroyWindow(_hwnd);
    _hwnd = 0;
    final cls = _className;
    if (cls != null) {
      _UnregisterClassW(cls, _GetModuleHandleW(nullptr));
      calloc.free(cls);
    }
    _className = null;
    _proc?.close();
    _proc = null;
  }
}
