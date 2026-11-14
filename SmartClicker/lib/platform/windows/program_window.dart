// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// The window of SmartClicker itself: tray icon, hide/show, the click marker,
// the selection frame and the mini panel.
part of 'windows_backend.dart';

mixin _ProgramWindow implements PlatformBackend {
  // From WindowsBackend itself.
  int get ownPid;

  WinTray? _tray;

  void Function(String)? _traySink;



  @override
  bool showTray(String tip, void Function(String event) onEvent) {
    _traySink = onEvent;
    _tray ??= WinTray((e) => _traySink?.call(e), owner: _findMainWindow());
    return _tray!.show(tip);
  }



  @override
  void hideTray() => _tray?.hide();



  @override
  void trayBalloon(String title, String text) => _tray?.balloon(title, text);



  @override
  int trayMenu(List<String> items, {int bold = -1}) =>
      _tray?.menu(items, bold: bold) ?? -1;



  @override
  void hideMainWindow() {
    final hwnd = _findMainWindow();
    if (hwnd != 0) _ShowWindow(hwnd, 0); // SW_HIDE
  }



  @override
  void showMainWindow() {
    final hwnd = _findMainWindow();
    if (hwnd == 0) return;
    _ShowWindow(hwnd, 5); // SW_SHOW
    activateSelf();
  }



  @override
  bool isMainMinimized() {
    final hwnd = _findMainWindow();
    return hwnd != 0 && _IsIconic(hwnd) != 0;
  }



  @override
  bool isMainVisible() {
    final hwnd = _findMainWindow();
    return hwnd != 0 && _IsWindowVisible(hwnd) != 0;
  }



  @override
  void activateSelf() {
    final hwnd = _findMainWindow();
    if (hwnd == 0) return;
    if (_IsIconic(hwnd) != 0) _ShowWindow(hwnd, 9); // SW_RESTORE
    focusWindow(hwnd);
  }

















































  /// Thread of the foreground window, and thread of the control that really
  /// has keyboard focus (they differ in WinUI/UWP apps such as Notepad).
  ({int foreground, int focus}) inputThreads() {
    final fg = _GetForegroundWindow();
    final fgThread = fg == 0 ? 0 : _GetWindowThreadProcessId(fg, nullptr);
    var focusThread = fgThread;
    final gti = calloc<Uint8>(72); // sizeof(GUITHREADINFO) on x64
    try {
      final d = ByteData.sublistView(gti.asTypedList(72));
      d.setUint32(0, 72, Endian.little);
      if (_GetGUIThreadInfo(0, gti) != 0) {
        final focus = d.getInt64(16, Endian.little); // hwndFocus
        if (focus != 0) {
          final t = _GetWindowThreadProcessId(focus, nullptr);
          if (t != 0) focusThread = t;
        }
      }
    } finally {
      calloc.free(gti);
    }
    return (foreground: fgThread, focus: focusThread);
  }





  // Helper windows exist only while shown: Flutter passes the close button
  // of the main window to the app (unsaved scripts, close to tray) only
  // when it is the process's single top-level window.
  static const _markerSize = 72;

  int _markerWnd = 0;

  int _markerDc = 0;

  /// A layered, click-through, always-on-top helper window.
  static int _overlayWindow(int w, int h) {
    final cls = 'Static'.toNativeUtf16();
    final title = ''.toNativeUtf16();
    // LAYERED | TRANSPARENT (click-through) | TOPMOST | TOOLWINDOW | NOACTIVATE
    final hwnd = _CreateWindowExW(0x00080000 | 0x20 | 0x8 | 0x80 | 0x08000000,
        cls, title, 0x80000000, 0, 0, w, h, 0, 0, 0, nullptr);
    calloc.free(cls);
    calloc.free(title);
    return hwnd;
  }

  void _ensureMarker() {
    const size = _markerSize;
    if (_markerWnd == 0) _markerWnd = _overlayWindow(size, size);
    if (_markerWnd == 0 || _markerDc != 0) return;

    final screen = _GetDC(0);
    _markerDc = _CreateCompatibleDC(screen);
    final bmi = calloc<Uint8>(64);
    final bitsPtr = calloc<Pointer<Uint8>>();
    try {
      final d = ByteData.sublistView(bmi.asTypedList(64));
      d.setUint32(0, 40, Endian.little);
      d.setInt32(4, size, Endian.little);
      d.setInt32(8, -size, Endian.little);
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      final bmp = _CreateDIBSection(screen, bmi, 0, bitsPtr, 0, 0);
      if (bmp == 0 || bitsPtr.value == nullptr) return;
      // A red ring with a soft edge; the centre stays fully transparent.
      final px = bitsPtr.value.asTypedList(size * size * 4);
      const c = (size - 1) / 2;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x - c, dy = y - c;
          final dist = math.sqrt(dx * dx + dy * dy);
          final t = (5.0 - (dist - 27).abs()).clamp(0.0, 1.0);
          final a = (235 * t).round();
          final i = (y * size + x) * 4;
          px[i] = 0x4D * a ~/ 255; // premultiplied B
          px[i + 1] = 0x48 * a ~/ 255; // G
          px[i + 2] = 0xF5 * a ~/ 255; // R
          px[i + 3] = a;
        }
      }
      _SelectObject(_markerDc, bmp);
    } finally {
      calloc.free(bmi);
      calloc.free(bitsPtr);
      _ReleaseDC(0, screen);
    }
  }



  @override
  void showMarker(int x, int y) {
    _ensureMarker();
    if (_markerWnd == 0 || _markerDc == 0) return;
    const size = _markerSize;
    final dst = calloc<Int32>(2);
    final sz = calloc<Int32>(2);
    final src = calloc<Int32>(2);
    final blend = calloc<Uint8>(4);
    try {
      dst[0] = x - size ~/ 2;
      dst[1] = y - size ~/ 2;
      sz[0] = size;
      sz[1] = size;
      blend[2] = 255; // SourceConstantAlpha
      blend[3] = 1; // AC_SRC_ALPHA
      _UpdateLayeredWindow(_markerWnd, 0, dst, sz, _markerDc, src, 0, blend, 2);
      _ShowWindow(_markerWnd, 4); // SW_SHOWNOACTIVATE
    } finally {
      calloc.free(dst);
      calloc.free(sz);
      calloc.free(src);
      calloc.free(blend);
    }
  }



  @override
  void hideMarker() {
    if (_markerWnd != 0) _DestroyWindow(_markerWnd);
    _markerWnd = 0; // the picture (DC) is kept for the next time
  }

  int _frameWnd = 0;



  @override
  void showFrame(int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) return hideFrame();
    if (_frameWnd == 0) {
      _frameWnd = _overlayWindow(8, 8);
      if (_frameWnd == 0) return;
    }
    const t = 3; // thickness, outside the rectangle
    final fw = w + 2 * t, fh = h + 2 * t;
    final screen = _GetDC(0);
    final dc = _CreateCompatibleDC(screen);
    final bmi = calloc<Uint8>(64);
    final bitsPtr = calloc<Pointer<Uint8>>();
    final dst = calloc<Int32>(2);
    final sz = calloc<Int32>(2);
    final src = calloc<Int32>(2);
    final blend = calloc<Uint8>(4);
    var bmp = 0;
    try {
      final d = ByteData.sublistView(bmi.asTypedList(64));
      d.setUint32(0, 40, Endian.little);
      d.setInt32(4, fw, Endian.little);
      d.setInt32(8, -fh, Endian.little);
      d.setUint16(12, 1, Endian.little);
      d.setUint16(14, 32, Endian.little);
      bmp = _CreateDIBSection(screen, bmi, 0, bitsPtr, 0, 0); // zeroed = clear
      if (bmp == 0 || bitsPtr.value == nullptr) return;
      final px = bitsPtr.value.asTypedList(fw * fh * 4);
      void dot(int px0, int py0) {
        final i = (py0 * fw + px0) * 4;
        px[i] = 0x4D; // B
        px[i + 1] = 0x48; // G
        px[i + 2] = 0xF5; // R
        px[i + 3] = 0xFF;
      }

      for (var k = 0; k < t; k++) {
        for (var xx = 0; xx < fw; xx++) {
          dot(xx, k);
          dot(xx, fh - 1 - k);
        }
        for (var yy = 0; yy < fh; yy++) {
          dot(k, yy);
          dot(fw - 1 - k, yy);
        }
      }
      final old = _SelectObject(dc, bmp);
      dst[0] = x - t;
      dst[1] = y - t;
      sz[0] = fw;
      sz[1] = fh;
      blend[2] = 255;
      blend[3] = 1;
      _UpdateLayeredWindow(_frameWnd, 0, dst, sz, dc, src, 0, blend, 2);
      _ShowWindow(_frameWnd, 4);
      _SelectObject(dc, old);
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



  @override
  void hideFrame() {
    if (_frameWnd != 0) _DestroyWindow(_frameWnd);
    _frameWnd = 0;
  }

  int _mainWnd = 0;

  ({int style, int ex, Rect4 rect, bool max})? _panelSaved;

  @override
  String? pickFolder({required String title, String? start}) {
    try {
      return pickFolderDialog(owner: _findMainWindow(), title: title, start: start);
    } finally {
      _adoptStrayWindows();
    }
  }

  /// The system file and folder dialogs leave a hidden shell window
  /// ("WorkerW") of this process behind. With a second window that has no
  /// owner Flutter no longer passes the close button to Dart: no question
  /// about unsaved scripts, and the process stayed alive without a window.
  /// Such windows get the main window as their owner.
  void _adoptStrayWindows() {
    final main = _findMainWindow();
    if (main == 0) return;
    final me = ownPid;
    final pidPtr = calloc<Uint32>();
    final buf = calloc<Uint16>(128).cast<Utf16>();
    try {
      var hwnd = _GetTopWindow(0);
      var guard = 0;
      while (hwnd != 0 && guard++ < 5000) {
        _GetWindowThreadProcessId(hwnd, pidPtr);
        if (pidPtr.value == me &&
            hwnd != main &&
            _GetWindow(hwnd, 4) == 0 && // GW_OWNER: none
            _GetClassNameW(hwnd, buf, 128) > 0 &&
            buf.toDartString() == 'WorkerW') {
          _SetWindowLongPtrW(hwnd, -8, main); // GWLP_HWNDPARENT = owner
          // Flutter counts windows by GetParent, which names the owner only
          // for WS_POPUP windows.
          final style = _GetWindowLongPtrW(hwnd, -16); // GWL_STYLE
          if (style & 0x40000000 == 0) {
            // not WS_CHILD
            _SetWindowLongPtrW(hwnd, -16, style | 0x80000000); // WS_POPUP
          }
        }
        hwnd = _GetWindow(hwnd, 2); // GW_HWNDNEXT
      }
    } finally {
      calloc.free(pidPtr);
      calloc.free(buf);
    }
  }

  int _findMainWindow() {
    if (_mainWnd != 0) return _mainWnd;
    final me = ownPid;
    final pidPtr = calloc<Uint32>();
    final buf = calloc<Uint16>(128).cast<Utf16>();
    try {
      var hwnd = _GetTopWindow(0);
      var guard = 0;
      while (hwnd != 0 && guard++ < 5000) {
        _GetWindowThreadProcessId(hwnd, pidPtr);
        if (pidPtr.value == me &&
            _GetClassNameW(hwnd, buf, 128) > 0 &&
            buf.toDartString() == 'FLUTTER_RUNNER_WIN32_WINDOW') {
          return _mainWnd = hwnd;
        }
        hwnd = _GetWindow(hwnd, 2); // GW_HWNDNEXT
      }
    } finally {
      calloc.free(pidPtr);
      calloc.free(buf);
    }
    return 0;
  }

  Rect4 _windowRect(int hwnd) {
    final rect = calloc<Int32>(4);
    try {
      _GetWindowRect(hwnd, rect);
      return (x: rect[0], y: rect[1], w: rect[2] - rect[0], h: rect[3] - rect[1]);
    } finally {
      calloc.free(rect);
    }
  }

  /// Windows 11: rounded corners for the borderless panel (ignored on 10).
  void _roundCorners(int hwnd, bool on) {
    try {
      final fn = DynamicLibrary.open('dwmapi.dll').lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Int32>, Uint32),
          int Function(int, int, Pointer<Int32>, int)>('DwmSetWindowAttribute');
      final v = calloc<Int32>()..value = on ? 2 : 0; // DWMWCP_ROUND / DEFAULT
      fn(hwnd, 33, v, 4); // DWMWA_WINDOW_CORNER_PREFERENCE
      calloc.free(v);
    } catch (_) {}
  }

  // SetWindowPos flags
  static const _swpNoSize = 0x0001, _swpNoZOrder = 0x0004;

  static const _swpNoActivate = 0x0010, _swpFrameChanged = 0x0020;

  static const _swpAsync = 0x4000; // never block on the window's own thread



  @override
  bool enterPanel(int? x, int? y, int w, int h) {
    final hwnd = _findMainWindow();
    if (hwnd == 0) return false;
    if (_panelSaved == null) {
      final max = _IsZoomed(hwnd) != 0;
      if (max || _IsIconic(hwnd) != 0) _ShowWindow(hwnd, 9); // SW_RESTORE
      final style = _GetWindowLongPtrW(hwnd, -16); // GWL_STYLE
      final ex = _GetWindowLongPtrW(hwnd, -20); // GWL_EXSTYLE
      _panelSaved = (style: style, ex: ex, rect: _windowRect(hwnd), max: max);
      // No caption and no sizing frame...
      _SetWindowLongPtrW(hwnd, -16, style & ~(0x00C00000 | 0x00040000));
      // ...never activated by a click (NOACTIVATE), still on the taskbar
      // (APPWINDOW).
      _SetWindowLongPtrW(hwnd, -20, ex | 0x08000000 | 0x00040000);
      _roundCorners(hwnd, true);
    }
    // Keep the panel inside the virtual screen (all monitors).
    final vx = _GetSystemMetrics(76), vy = _GetSystemMetrics(77);
    final vw = _GetSystemMetrics(78), vh = _GetSystemMetrics(79);
    final px = (x ?? screenSize().w - w - 24)
        .clamp(vx, math.max(vx, vx + vw - w))
        .toInt();
    final py = (y ?? 24).clamp(vy, math.max(vy, vy + vh - h)).toInt();
    _SetWindowPos(hwnd, -1 /* HWND_TOPMOST */, px, py, w, h,
        _swpFrameChanged | _swpNoActivate | _swpAsync);
    return true;
  }



  @override
  void leavePanel({bool activate = true}) {
    final saved = _panelSaved;
    final hwnd = _mainWnd;
    if (saved == null || hwnd == 0) return;
    _panelSaved = null;
    _SetWindowLongPtrW(hwnd, -16, saved.style);
    _SetWindowLongPtrW(hwnd, -20, saved.ex);
    _roundCorners(hwnd, false);
    _SetWindowPos(hwnd, -2 /* HWND_NOTOPMOST */, saved.rect.x, saved.rect.y,
        saved.rect.w, saved.rect.h, _swpFrameChanged | _swpAsync);
    if (saved.max) _ShowWindow(hwnd, 3); // SW_MAXIMIZE
    if (activate && _SetForegroundWindow(hwnd) == 0) focusWindow(hwnd);
  }



  @override
  void movePanel(int x, int y) {
    if (_panelSaved == null || _mainWnd == 0) return;
    _SetWindowPos(_mainWnd, 0, x, y, 0, 0,
        _swpNoSize | _swpNoZOrder | _swpNoActivate | _swpAsync);
  }



  @override
  Rect4? panelBounds() =>
      _panelSaved == null || _mainWnd == 0 ? null : _windowRect(_mainWnd);


}
