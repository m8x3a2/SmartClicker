// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// Stop frame for taking a point: a still picture of the screen over all
// windows (clicks land on it, nothing under the cursor lights up) and the
// magnifier next to the cursor.
part of 'windows_backend.dart';

final _LoadCursorW = _user32.lookupFunction<IntPtr Function(IntPtr, IntPtr),
    int Function(int, int)>('LoadCursorW');
final _RegisterClassExW = _user32.lookupFunction<Uint16 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('RegisterClassExW');

/// The stop frame needs no code of its own: the default window procedure
/// does nothing with clicks, and the class gives it the cross cursor.
final _defWindowProc = _user32
    .lookup<NativeFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr)>>('DefWindowProcW');

const _freezeClass = 'SmartClickerFreeze';

mixin _FreezeWindow implements PlatformBackend {
  int _freezeWnd = 0;
  int _loupeWnd = 0;
  bool _freezeClassReady = false;

  int _findMainWindow(); // from _ProgramWindow
  int get _frameWnd; // from _ProgramWindow
  ({int style, int ex, Rect4 rect, bool max})? get _panelSaved; // from _ProgramWindow

  @override
  Rect4 virtualScreen() => (
        x: _GetSystemMetrics(76),
        y: _GetSystemMetrics(77),
        w: _GetSystemMetrics(78),
        h: _GetSystemMetrics(79),
      );

  void _registerFreezeClass() {
    if (_freezeClassReady) return;
    final cls = _freezeClass.toNativeUtf16();
    final wc = calloc<Uint8>(80);
    try {
      final d = ByteData.sublistView(wc.asTypedList(80));
      d.setUint32(0, 80, Endian.little); // cbSize
      d.setUint64(8, _defWindowProc.address, Endian.little); // lpfnWndProc
      d.setUint64(24, _GetModuleHandleW(nullptr), Endian.little); // hInstance
      d.setUint64(40, _LoadCursorW(0, 32515), Endian.little); // hCursor: IDC_CROSS
      d.setUint64(64, cls.address, Endian.little); // lpszClassName
      _RegisterClassExW(wc); // fails harmlessly if registered before
      _freezeClassReady = true;
    } finally {
      calloc.free(wc);
      calloc.free(cls);
    }
  }

  @override
  bool showFreeze(int x, int y, int w, int h, Uint8List bgra) {
    if (w <= 0 || h <= 0 || bgra.length < w * h * 4) return false;
    hideFreeze();
    _registerFreezeClass();
    final cls = _freezeClass.toNativeUtf16();
    final title = ''.toNativeUtf16();
    // LAYERED | TOPMOST | TOOLWINDOW | NOACTIVATE — not click-through: the
    // clicks must stay here. No owner: an owned window would always be
    // above the mini panel (the panel is the main window).
    _freezeWnd = _CreateWindowExW(0x00080000 | 0x8 | 0x80 | 0x08000000, cls, title, 0x80000000,
        x, y, w, h, 0, 0, _GetModuleHandleW(nullptr), nullptr);
    calloc.free(cls);
    calloc.free(title);
    if (_freezeWnd == 0) return false;
    if (!_paintLayered(_freezeWnd, x, y, w, h, bgra)) {
      hideFreeze();
      return false;
    }
    // The mini panel (with its cancel button) stays above the stop frame.
    if (_panelSaved != null) {
      final main = _findMainWindow();
      if (main != 0) _SetWindowPos(main, -1 /* HWND_TOPMOST */, 0, 0, 0, 0, 0x1 | 0x2 | 0x10);
    }
    return true;
  }

  @override
  void hideFreeze() {
    if (_freezeWnd != 0) _DestroyWindow(_freezeWnd);
    _freezeWnd = 0;
  }

  @override
  bool freezeAt(int x, int y) =>
      _freezeWnd != 0 && _WindowFromPoint((y << 32) | (x & 0xFFFFFFFF)) == _freezeWnd;

  @override
  void showLoupe(int x, int y, int w, int h, Uint8List bgra) {
    if (_loupeWnd == 0) {
      final cls = 'Static'.toNativeUtf16();
      final title = ''.toNativeUtf16();
      // LAYERED | TRANSPARENT (click-through) | TOPMOST | TOOLWINDOW | NOACTIVATE
      _loupeWnd = _CreateWindowExW(0x00080000 | 0x20 | 0x8 | 0x80 | 0x08000000, cls, title,
          0x80000000, x, y, w, h, 0, 0, 0, nullptr);
      calloc.free(cls);
      calloc.free(title);
      if (_loupeWnd == 0) return;
    }
    _paintLayered(_loupeWnd, x, y, w, h, bgra);
  }

  @override
  void hideLoupe() {
    if (_loupeWnd != 0) _DestroyWindow(_loupeWnd);
    _loupeWnd = 0;
  }

  @override
  void raisePickOverlays() {
    if (_freezeWnd == 0) return;
    void raise(int hwnd) {
      // HWND_TOPMOST, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
      if (hwnd != 0) _SetWindowPos(hwnd, -1, 0, 0, 0, 0, 0x1 | 0x2 | 0x10);
    }

    if (_panelSaved != null) raise(_findMainWindow());
    raise(_frameWnd);
    raise(_loupeWnd);
  }

  /// Puts a premultiplied BGRA picture into a layered window at (x, y).
  bool _paintLayered(int hwnd, int x, int y, int w, int h, Uint8List bgra) {
    final screen = _GetDC(0);
    final dc = _CreateCompatibleDC(screen);
    final bmi = calloc<Uint8>(64);
    final bitsPtr = calloc<Pointer<Uint8>>();
    final dst = calloc<Int32>(2), sz = calloc<Int32>(2), src = calloc<Int32>(2);
    final blend = calloc<Uint8>(4);
    var bmp = 0;
    try {
      final d = ByteData.sublistView(bmi.asTypedList(64));
      d.setUint32(0, 40, Endian.little);
      d.setInt32(4, w, Endian.little);
      d.setInt32(8, -h, Endian.little); // top-down rows
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      bmp = _CreateDIBSection(screen, bmi, 0, bitsPtr, 0, 0);
      if (bmp == 0 || bitsPtr.value == nullptr) return false;
      bitsPtr.value.asTypedList(w * h * 4).setRange(0, w * h * 4, bgra);
      final old = _SelectObject(dc, bmp);
      dst[0] = x;
      dst[1] = y;
      sz[0] = w;
      sz[1] = h;
      blend[2] = 255; // SourceConstantAlpha
      blend[3] = 1; // AC_SRC_ALPHA
      final ok = _UpdateLayeredWindow(hwnd, 0, dst, sz, dc, src, 0, blend, 2) != 0;
      _ShowWindow(hwnd, 4); // SW_SHOWNOACTIVATE
      _SelectObject(dc, old);
      return ok;
    } finally {
      if (bmp != 0) _DeleteObject(bmp);
      _DeleteDC(dc);
      _ReleaseDC(0, screen);
      calloc.free(bmi);
      calloc.free(bitsPtr);
      calloc.free(dst);
      calloc.free(sz);
      calloc.free(src);
      calloc.free(blend);
    }
  }
}
