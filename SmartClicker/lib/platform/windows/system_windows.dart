// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// Windows, processes, rights, power, battery, network, clipboard and the file
// dialog of the Windows backend.
part of 'windows_backend.dart';

mixin _SystemWindows implements PlatformBackend {
  // From WindowsBackend itself.
  int get ownPid;
  void _vkEvent(int vk, bool down);

  /// Returns (pid, exe name) for every running process.
  List<(int, String)> _processList() {
    final out = <(int, String)>[];
    final snap = _CreateToolhelp32Snapshot(0x2, 0);
    if (snap == -1 || snap == 0) return out;
    const size = 568; // sizeof(PROCESSENTRY32W) on x64
    final e = calloc<Uint8>(size);
    try {
      final d = ByteData.sublistView(e.asTypedList(size));
      d.setUint32(0, size, Endian.little);
      var ok = _Process32FirstW(snap, e);
      while (ok != 0) {
        final pid = d.getUint32(8, Endian.little);
        out.add((pid, (e + 44).cast<Utf16>().toDartString()));
        ok = _Process32NextW(snap, e);
      }
    } finally {
      calloc.free(e);
      _CloseHandle(snap);
    }
    return out;
  }

  String _processName(int pid) {
    final h = _OpenProcess(0x1000, 0, pid); // QUERY_LIMITED_INFORMATION
    if (h == 0) return '';
    final buf = calloc<Uint16>(520).cast<Utf16>();
    final size = calloc<Uint32>()..value = 520;
    try {
      if (_QueryFullProcessImageNameW(h, 0, buf, size) == 0) return '';
      final path = buf.toDartString();
      return path.substring(path.lastIndexOf('\\') + 1);
    } finally {
      calloc.free(buf);
      calloc.free(size);
      _CloseHandle(h);
    }
  }

  WindowInfo? _info(int hwnd, Map<int, String> procCache) {
    final buf = calloc<Uint16>(512).cast<Utf16>();
    final pidPtr = calloc<Uint32>();
    final rect = calloc<Int32>(4);
    try {
      final len = _GetWindowTextW(hwnd, buf, 512);
      final title = len > 0 ? buf.toDartString() : '';
      _GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      _GetWindowRect(hwnd, rect);
      final proc = procCache.putIfAbsent(pid, () => _processName(pid));
      return WindowInfo(hwnd, title, proc, pid, rect[0], rect[1],
          rect[2] - rect[0], rect[3] - rect[1]);
    } finally {
      calloc.free(buf);
      calloc.free(pidPtr);
      calloc.free(rect);
    }
  }

  @override
  List<WindowInfo> windows() {
    final out = <WindowInfo>[];
    final cache = <int, String>{};
    var hwnd = _GetTopWindow(0);
    var guard = 0;
    while (hwnd != 0 && guard++ < 5000) {
      if (_IsWindowVisible(hwnd) != 0) {
        final info = _info(hwnd, cache);
        if (info != null && info.title.isNotEmpty && info.w > 0 && info.h > 0 &&
            !_isPopupHost(info)) {
          out.add(info);
        }
      }
      hwnd = _GetWindow(hwnd, 2); // GW_HWNDNEXT
    }
    return out;
  }

  /// Windows 11 apps (Notepad, Paint...) briefly show tiny service windows
  /// titled "PopupHost" (tab previews, tooltips). They are not windows a
  /// script or the user means: lists would show them and the autorun would
  /// take one appearing for "the program started".
  static bool _isPopupHost(WindowInfo w) => w.title == 'PopupHost' && w.w < 200 && w.h < 200;

  @override
  WindowInfo? activeWindow() {
    final hwnd = _GetForegroundWindow();
    return hwnd == 0 ? null : _info(hwnd, {});
  }

  @override
  int pidAt(int x, int y) {
    final hwnd = _WindowFromPoint((y << 32) | (x & 0xFFFFFFFF));
    if (hwnd == 0) return 0;
    final pidPtr = calloc<Uint32>();
    try {
      _GetWindowThreadProcessId(hwnd, pidPtr);
      return pidPtr.value;
    } finally {
      calloc.free(pidPtr);
    }
  }

  @override
  WindowInfo? windowAt(int x, int y) {
    // POINT is passed by value: x in the low 32 bits, y in the high ones.
    final packed = (y << 32) | (x & 0xFFFFFFFF);
    final hwnd = _WindowFromPoint(packed);
    if (hwnd == 0) return null;
    final root = _GetAncestor(hwnd, 2); // GA_ROOT
    return _info(root == 0 ? hwnd : root, {});
  }

  @override
  bool focusWindow(int handle) {
    if (_IsIconic(handle) != 0) _ShowWindow(handle, 9); // SW_RESTORE
    if (_GetForegroundWindow() == handle) return true;
    if (_SetForegroundWindow(handle) != 0 && _GetForegroundWindow() == handle) return true;
    // Windows lets only the program the user works with change the active
    // window. Sharing its input state lifts that lock. (A tap of Alt does it
    // too, but Alt alone opens the menu / key tips of the window that gets
    // it — the Windows 11 Notepad then swallows the next keys.)
    final fg = _GetForegroundWindow();
    final me = _GetCurrentThreadId();
    final other = fg == 0 ? 0 : _GetWindowThreadProcessId(fg, nullptr);
    final attached = other != 0 && other != me && _AttachThreadInput(me, other, 1) != 0;
    try {
      _BringWindowToTop(handle);
      _SetForegroundWindow(handle);
    } finally {
      if (attached) _AttachThreadInput(me, other, 0);
    }
    if (_GetForegroundWindow() == handle) return true;
    // Last resort: an input event of our own lifts the lock; F24 does nothing
    // in programs (unlike Alt).
    _vkEvent(0x87, true);
    _vkEvent(0x87, false);
    _SetForegroundWindow(handle);
    return _GetForegroundWindow() == handle;
  }

  @override
  bool setWindowBounds(int handle, int x, int y, int w, int h) {
    if (_IsIconic(handle) != 0) _ShowWindow(handle, 9);
    return _SetWindowPos(handle, 0, x, y, w, h, 0x0004 | 0x0010) != 0;
  }

  @override
  Rect4? clientRect(int handle) {
    final rect = calloc<Int32>(4);
    final pt = calloc<Int32>(2);
    try {
      if (_GetClientRect(handle, rect) == 0) return null;
      _ClientToScreen(handle, pt);
      return (x: pt[0], y: pt[1], w: rect[2], h: rect[3]);
    } finally {
      calloc.free(rect);
      calloc.free(pt);
    }
  }

  @override
  List<String> processes() => _processList().map((p) => p.$2).toList();

  @override
  int killProcess(String name) {
    final q = name.toLowerCase();
    var killed = 0;
    for (final (pid, exe) in _processList()) {
      final n = exe.toLowerCase();
      if (n != q && n != '$q.exe') continue;
      if (pid == ownPid) continue;
      final h = _OpenProcess(0x0001, 0, pid); // PROCESS_TERMINATE
      if (h == 0) continue;
      if (_TerminateProcess(h, 1) != 0) killed++;
      _CloseHandle(h);
    }
    return killed;
  }

  /// Pids of the processes named [name] (with or without .exe).
  Iterable<int> _pidsNamed(String name) {
    final q = name.toLowerCase();
    return [
      for (final (pid, exe) in _processList())
        if (exe.toLowerCase() == q || exe.toLowerCase() == '$q.exe') pid,
    ];
  }

  @override
  ({int idle, int total})? cpuTimes() {
    final t = calloc<Uint64>(3);
    try {
      if (_GetSystemTimes(t, t + 1, t + 2) == 0) return null;
      return (idle: t[0], total: t[1] + t[2]); // kernel time includes idle
    } finally {
      calloc.free(t);
    }
  }

  @override
  Map<int, int> processCpuTimes(String name) {
    final out = <int, int>{};
    final t = calloc<Uint64>(4);
    try {
      for (final pid in _pidsNamed(name)) {
        final h = _OpenProcess(0x1000, 0, pid); // QUERY_LIMITED_INFORMATION
        if (h == 0) continue;
        if (_GetProcessTimes(h, t, t + 1, t + 2, t + 3) != 0) {
          out[pid] = t[2] + t[3];
        }
        _CloseHandle(h);
      }
    } finally {
      calloc.free(t);
    }
    return out;
  }

  @override
  ({int total, int free})? memoryStatus() {
    const size = 64; // sizeof(MEMORYSTATUSEX)
    final m = calloc<Uint8>(size);
    try {
      final d = ByteData.sublistView(m.asTypedList(size));
      d.setUint32(0, size, Endian.little);
      if (_GlobalMemoryStatusEx(m) == 0) return null;
      return (
        total: d.getUint64(8, Endian.little),
        free: d.getUint64(16, Endian.little),
      );
    } finally {
      calloc.free(m);
    }
  }

  @override
  int? processMemory(String name) {
    const size = 80; // sizeof(PROCESS_MEMORY_COUNTERS_EX) on x64
    final m = calloc<Uint8>(size);
    int? sum;
    try {
      final d = ByteData.sublistView(m.asTypedList(size));
      for (final pid in _pidsNamed(name)) {
        final h = _OpenProcess(0x1000, 0, pid); // QUERY_LIMITED_INFORMATION
        if (h == 0) continue;
        d.setUint32(0, size, Endian.little);
        if (_K32GetProcessMemoryInfo(h, m, size) != 0) {
          sum = (sum ?? 0) + d.getUint64(16, Endian.little); // WorkingSetSize
        }
        _CloseHandle(h);
      }
    } finally {
      calloc.free(m);
    }
    return sum;
  }

  static final _advapi = DynamicLibrary.open('advapi32.dll');

  static final _OpenProcessToken = _advapi.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
      int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken');

  static final _GetTokenInformation = _advapi.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint32>, Uint32, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint32>, int, Pointer<Uint32>)>('GetTokenInformation');

  @override
  bool isElevated() => isProcessElevated(ownPid) ?? false;

  @override
  bool? isProcessElevated(int pid) {
    final h = _OpenProcess(0x1000, 0, pid); // QUERY_LIMITED_INFORMATION
    if (h == 0) return null;
    final token = calloc<IntPtr>();
    final value = calloc<Uint32>();
    final len = calloc<Uint32>();
    try {
      // An elevated program does not let an ordinary one read its token.
      if (_OpenProcessToken(h, 0x8, token) == 0) return null; // TOKEN_QUERY
      final ok = _GetTokenInformation(token.value, 20, value, 4, len); // TokenElevation
      _CloseHandle(token.value);
      return ok == 0 ? null : value.value != 0;
    } finally {
      _CloseHandle(h);
      calloc.free(token);
      calloc.free(value);
      calloc.free(len);
    }
  }

  @override
  bool restartElevated() => _relaunch('runas');

  @override
  bool restartSelf() => _relaunch('open');

  /// Starts this exe again through the shell ("runas" = as administrator).
  /// Process.start would give the new window a warning icon in its title.
  bool _relaunch(String verbName) {
    final fn = DynamicLibrary.open('shell32.dll').lookupFunction<
        IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
            Pointer<Utf16>, Int32),
        int Function(int, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>,
            Pointer<Utf16>, int)>('ShellExecuteW');
    final verb = verbName.toNativeUtf16();
    final file = Platform.resolvedExecutable.toNativeUtf16();
    // The new copy waits until this one quits (see SingleInstance).
    final args = '--restarted'.toNativeUtf16();
    try {
      return fn(0, verb, file, args, nullptr, 1) > 32; // SW_SHOWNORMAL
    } finally {
      calloc.free(verb);
      calloc.free(file);
      calloc.free(args);
    }
  }

  @override
  List<String> ocrLanguages() {
    try {
      return winocr.ocrLanguages();
    } catch (_) {
      return const [];
    }
  }

  /// Turns on SeShutdownPrivilege (every user has it, disabled by default);
  /// needed for sleep, shutdown and restart.
  bool _enableShutdownPrivilege() {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final openToken = advapi.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
        int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken');
    final lookup = advapi.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint8>),
        int Function(Pointer<Utf16>, Pointer<Utf16>,
            Pointer<Uint8>)>('LookupPrivilegeValueW');
    final adjust = advapi.lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint8>,
            Pointer<Uint32>),
        int Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>,
            Pointer<Uint32>)>('AdjustTokenPrivileges');
    final token = calloc<IntPtr>();
    final tp = calloc<Uint8>(16); // TOKEN_PRIVILEGES with one LUID_AND_ATTRIBUTES
    final priv = 'SeShutdownPrivilege'.toNativeUtf16();
    try {
      // TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY
      if (openToken(_GetCurrentProcess(), 0x28, token) == 0) return false;
      final d = ByteData.sublistView(tp.asTypedList(16));
      d.setUint32(0, 1, Endian.little);
      if (lookup(nullptr, priv, tp + 4) == 0) return false;
      d.setUint32(12, 2, Endian.little); // SE_PRIVILEGE_ENABLED
      final ok = adjust(token.value, 0, tp, 0, nullptr, nullptr) != 0;
      _CloseHandle(token.value);
      return ok;
    } finally {
      calloc.free(token);
      calloc.free(tp);
      calloc.free(priv);
    }
  }

  @override
  bool systemPower(String action) {
    if (action == 'lock') {
      final fn = _user32.lookupFunction<Int32 Function(), int Function()>(
          'LockWorkStation');
      return fn() != 0;
    }
    _enableShutdownPrivilege();
    if (action == 'sleep' || action == 'hibernate') {
      final powrprof = DynamicLibrary.open('powrprof.dll');
      final fn = powrprof.lookupFunction<Uint8 Function(Uint8, Uint8, Uint8),
          int Function(int, int, int)>('SetSuspendState');
      return fn(action == 'hibernate' ? 1 : 0, 0, 0) != 0;
    }
    final flags = switch (action) {
      'shutdown' => 0x8, // EWX_POWEROFF
      'restart' => 0x2, // EWX_REBOOT
      'logoff' => 0x0, // EWX_LOGOFF
      _ => -1,
    };
    if (flags < 0) return false;
    final exit = _user32.lookupFunction<Int32 Function(Uint32, Uint32),
        int Function(int, int)>('ExitWindowsEx');
    // SHTDN_REASON_FLAG_PLANNED | SHTDN_REASON_MAJOR_APPLICATION; no
    // EWX_FORCE: programs with unsaved work may ask the user first.
    return exit(flags, 0x80040000) != 0;
  }

  Uint8List? _power() {
    final p = calloc<Uint8>(12);
    try {
      if (_GetSystemPowerStatus(p) == 0) return null;
      return Uint8List.fromList(p.asTypedList(12));
    } finally {
      calloc.free(p);
    }
  }

  @override
  int? batteryLevel() {
    final p = _power();
    if (p == null || p[2] == 255 || (p[1] & 128) != 0) return null;
    return p[2];
  }

  @override
  bool? isCharging() {
    final p = _power();
    if (p == null || p[0] == 255) return null;
    return p[0] == 1;
  }

  @override
  bool networkConnected() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final fn = wininet.lookupFunction<
          Int32 Function(Pointer<Uint32>, Uint32),
          int Function(Pointer<Uint32>, int)>('InternetGetConnectedState');
      final flags = calloc<Uint32>();
      try {
        return fn(flags, 0) != 0;
      } finally {
        calloc.free(flags);
      }
    } catch (_) {
      return false;
    }
  }

  bool _openClipboard() {
    for (var i = 0; i < 10; i++) {
      if (_OpenClipboard(0) != 0) return true;
    }
    return false;
  }

  @override
  String getClipboard() {
    if (!_openClipboard()) return '';
    try {
      final h = _GetClipboardData(13); // CF_UNICODETEXT
      if (h == 0) return '';
      final p = _GlobalLock(h);
      if (p == nullptr) return '';
      try {
        return p.cast<Utf16>().toDartString();
      } finally {
        _GlobalUnlock(h);
      }
    } finally {
      _CloseClipboard();
    }
  }

  @override
  void setClipboard(String text) {
    final units = text.codeUnits;
    if (!_openClipboard()) throw StateError('буфер обмена занят');
    try {
      _EmptyClipboard();
      final h = _GlobalAlloc(0x0002, (units.length + 1) * 2);
      if (h == 0) return;
      final p = _GlobalLock(h);
      for (var i = 0; i < units.length; i++) {
        p[i] = units[i];
      }
      p[units.length] = 0;
      _GlobalUnlock(h);
      _SetClipboardData(13, h);
    } finally {
      _CloseClipboard();
    }
  }

  @override
  String? pickFile(
      {required bool save, required String title, String defaultName = '', String ext = 'zip'}) {
    const maxPath = 1024;
    final ofn = calloc<Uint8>(152); // sizeof(OPENFILENAMEW) on x64
    final file = calloc<Uint16>(maxPath);
    // Filter: "ZIP\0*.zip\0\0"
    final filterUnits = [...'${ext.toUpperCase()} (*.$ext)'.codeUnits, 0, ...'*.$ext'.codeUnits, 0, 0];
    final filter = calloc<Uint16>(filterUnits.length);
    final titlePtr = title.toNativeUtf16();
    final extPtr = ext.toNativeUtf16();
    try {
      for (var i = 0; i < filterUnits.length; i++) {
        filter[i] = filterUnits[i];
      }
      final name = defaultName.codeUnits;
      for (var i = 0; i < name.length && i < maxPath - 1; i++) {
        file[i] = name[i];
      }
      final d = ByteData.sublistView(ofn.asTypedList(152));
      d.setUint32(0, 152, Endian.little);
      d.setInt64(8, _GetForegroundWindow(), Endian.little); // owner
      d.setInt64(24, filter.address, Endian.little);
      d.setUint32(44, 1, Endian.little); // filter index
      d.setInt64(48, file.address, Endian.little);
      d.setUint32(56, maxPath, Endian.little);
      d.setInt64(88, titlePtr.address, Endian.little);
      // EXPLORER | NOCHANGEDIR | PATHMUSTEXIST (+ FILEMUSTEXIST / OVERWRITEPROMPT)
      d.setUint32(96, 0x80000 | 0x8 | 0x800 | (save ? 0x2 : 0x1000), Endian.little);
      d.setInt64(104, extPtr.address, Endian.little);
      final comdlg = DynamicLibrary.open('comdlg32.dll');
      final fn = comdlg.lookupFunction<Int32 Function(Pointer<Uint8>),
              int Function(Pointer<Uint8>)>(
          save ? 'GetSaveFileNameW' : 'GetOpenFileNameW');
      if (fn(ofn) == 0) return null;
      return file.cast<Utf16>().toDartString();
    } finally {
      calloc.free(ofn);
      calloc.free(file);
      calloc.free(filter);
      calloc.free(titlePtr);
      calloc.free(extPtr);
    }
  }
}
