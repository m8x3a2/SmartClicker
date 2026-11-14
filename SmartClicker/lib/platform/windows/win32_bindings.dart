// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names
// Win32 functions used by the backend (user32, gdi32, kernel32) via dart:ffi,
// and the low-level mouse hook for recording the wheel.
part of 'windows_backend.dart';

final _user32 = DynamicLibrary.open('user32.dll');

final _gdi32 = DynamicLibrary.open('gdi32.dll');

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _GetSystemMetrics = _user32
    .lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');

final _GetCursorPos = _user32.lookupFunction<Int32 Function(Pointer<Int32>),
    int Function(Pointer<Int32>)>('GetCursorPos');

final _SetCursorPos = _user32.lookupFunction<Int32 Function(Int32, Int32),
    int Function(int, int)>('SetCursorPos');

final _SendInput = _user32.lookupFunction<
    Uint32 Function(Uint32, Pointer<Uint8>, Int32),
    int Function(int, Pointer<Uint8>, int)>('SendInput');

final _MapVirtualKeyW = _user32.lookupFunction<Uint32 Function(Uint32, Uint32),
    int Function(int, int)>('MapVirtualKeyW');

final _GetAsyncKeyState = _user32
    .lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');

final _GetDC =
    _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');

final _ReleaseDC = _user32.lookupFunction<Int32 Function(IntPtr, IntPtr),
    int Function(int, int)>('ReleaseDC');

final _GetForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

final _GetTopWindow = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetTopWindow');

final _GetWindow = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32),
    int Function(int, int)>('GetWindow');

final _IsWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');

final _IsIconic =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');

final _GetWindowTextW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');

final _GetWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');

final _GetWindowRect = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Int32>),
    int Function(int, Pointer<Int32>)>('GetWindowRect');

final _GetClientRect = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Int32>),
    int Function(int, Pointer<Int32>)>('GetClientRect');

final _ClientToScreen = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Int32>),
    int Function(int, Pointer<Int32>)>('ClientToScreen');

final _SetForegroundWindow = _user32.lookupFunction<Int32 Function(IntPtr),
    int Function(int)>('SetForegroundWindow');

final _ShowWindow = _user32.lookupFunction<Int32 Function(IntPtr, Int32),
    int Function(int, int)>('ShowWindow');

final _SetWindowPos = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');

final _OpenClipboard = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');

final _CloseClipboard =
    _user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');

final _EmptyClipboard =
    _user32.lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');

final _GetClipboardData = _user32
    .lookupFunction<IntPtr Function(Uint32), int Function(int)>('GetClipboardData');

final _SetClipboardData = _user32.lookupFunction<
    IntPtr Function(Uint32, IntPtr), int Function(int, int)>('SetClipboardData');

final _WindowFromPoint = _user32
    .lookupFunction<IntPtr Function(Int64), int Function(int)>('WindowFromPoint');

final _GetAncestor = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32),
    int Function(int, int)>('GetAncestor');

final _GetKeyboardLayout =_user32.lookupFunction<IntPtr Function(Uint32),
    int Function(int)>('GetKeyboardLayout');

final _DestroyWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyWindow');

final _CreateWindowExW = _user32.lookupFunction<
    IntPtr Function(Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32, Int32,
        Int32, Int32, Int32, IntPtr, IntPtr, IntPtr, Pointer<Void>),
    int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, int, int, int, int,
        int, int, int, Pointer<Void>)>('CreateWindowExW');

final _UpdateLayeredWindow = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Pointer<Int32>, Pointer<Int32>, IntPtr,
        Pointer<Int32>, Uint32, Pointer<Uint8>, Uint32),
    int Function(int, int, Pointer<Int32>, Pointer<Int32>, int, Pointer<Int32>,
        int, Pointer<Uint8>, int)>('UpdateLayeredWindow');

final _CreateDIBSection = _gdi32.lookupFunction<
    IntPtr Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Pointer<Uint8>>,
        IntPtr, Uint32),
    int Function(int, Pointer<Uint8>, int, Pointer<Pointer<Uint8>>, int,
        int)>('CreateDIBSection');

final _GetGUIThreadInfo = _user32.lookupFunction<
    Int32 Function(Uint32, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('GetGUIThreadInfo');

final _GetClassNameW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetClassNameW');

final _GetWindowLongPtrW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongPtrW');

final _SetWindowLongPtrW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32, IntPtr),
    int Function(int, int, int)>('SetWindowLongPtrW');

final _IsZoomed =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsZoomed');

final _SetWindowsHookExW = _user32.lookupFunction<
    IntPtr Function(Int32, Pointer<NativeFunction<_HookProc>>, IntPtr, Uint32),
    int Function(int, Pointer<NativeFunction<_HookProc>>, int,
        int)>('SetWindowsHookExW');

final _UnhookWindowsHookEx = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('UnhookWindowsHookEx');

final _CallNextHookEx = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('CallNextHookEx');

final _GetCurrentThreadId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

final _AttachThreadInput = _user32.lookupFunction<Int32 Function(Uint32, Uint32, Int32),
    int Function(int, int, int)>('AttachThreadInput');

final _BringWindowToTop =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('BringWindowToTop');

final _GetModuleHandleW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>),
    int Function(Pointer<Utf16>)>('GetModuleHandleW');

typedef _HookProc = IntPtr Function(Int32, IntPtr, IntPtr);

final _GetMessageW = _user32.lookupFunction<
    Int32 Function(Pointer<Uint8>, IntPtr, Uint32, Uint32),
    int Function(Pointer<Uint8>, int, int, int)>('GetMessageW');

final _PeekMessageW = _user32.lookupFunction<
    Int32 Function(Pointer<Uint8>, IntPtr, Uint32, Uint32, Uint32),
    int Function(Pointer<Uint8>, int, int, int, int)>('PeekMessageW');

final _GetTickCount =
    _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetTickCount');

final _PostThreadMessageW = _user32.lookupFunction<
    Int32 Function(Uint32, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('PostThreadMessageW');

void Function(int delta, bool horizontal, int x, int y)? _wheelSink;

/// WH_MOUSE_LL procedure: runs for every mouse event in the system while
/// the wheel is watched, so it does next to nothing.
int _mouseHook(int code, int wParam, int lParam) {
  if (code == 0 && (wParam == 0x020A || wParam == 0x020E)) {
    final sink = _wheelSink;
    if (sink != null) {
      final p = Pointer<Int32>.fromAddress(lParam); // MSLLHOOKSTRUCT
      final delta = (p[2] >> 16).toSigned(16);
      try {
        sink(delta, wParam == 0x020E, p[0], p[1]);
      } catch (_) {}
    }
  }
  return _CallNextHookEx(0, code, wParam, lParam);
}

final _GetKeyState =
    _user32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetKeyState');

final _ToUnicodeEx = _user32.lookupFunction<
    Int32 Function(Uint32, Uint32, Pointer<Uint8>, Pointer<Uint16>, Int32,
        Uint32, IntPtr),
    int Function(int, int, Pointer<Uint8>, Pointer<Uint16>, int, int,
        int)>('ToUnicodeEx');

final _GetPixel =_gdi32.lookupFunction<Uint32 Function(IntPtr, Int32, Int32),
    int Function(int, int, int)>('GetPixel');

final _CreateCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');

final _CreateCompatibleBitmap = _gdi32.lookupFunction<
    IntPtr Function(IntPtr, Int32, Int32),
    int Function(int, int, int)>('CreateCompatibleBitmap');

final _SelectObject = _gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr),
    int Function(int, int)>('SelectObject');

final _BitBlt = _gdi32.lookupFunction<
    Int32 Function(
        IntPtr, Int32, Int32, Int32, Int32, IntPtr, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int, int, int)>('BitBlt');

final _GetDIBits = _gdi32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Uint8>,
        Pointer<Uint8>, Uint32),
    int Function(int, int, int, int, Pointer<Uint8>, Pointer<Uint8>,
        int)>('GetDIBits');

final _DeleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');

final _DeleteDC =
    _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');

final _OpenProcess = _kernel32.lookupFunction<
    IntPtr Function(Uint32, Int32, Uint32),
    int Function(int, int, int)>('OpenProcess');

final _CloseHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final _QueryFullProcessImageNameW = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
    int Function(int, int, Pointer<Utf16>,
        Pointer<Uint32>)>('QueryFullProcessImageNameW');

final _TerminateProcess = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Uint32), int Function(int, int)>('TerminateProcess');

final _CreateToolhelp32Snapshot = _kernel32.lookupFunction<
    IntPtr Function(Uint32, Uint32),
    int Function(int, int)>('CreateToolhelp32Snapshot');

final _Process32FirstW = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('Process32FirstW');

final _Process32NextW = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>)>('Process32NextW');

final _GetSystemPowerStatus = _kernel32.lookupFunction<
    Int32 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('GetSystemPowerStatus');

final _GlobalAlloc = _kernel32.lookupFunction<IntPtr Function(Uint32, IntPtr),
    int Function(int, int)>('GlobalAlloc');

final _GlobalLock = _kernel32.lookupFunction<Pointer<Uint16> Function(IntPtr),
    Pointer<Uint16> Function(int)>('GlobalLock');

final _GlobalUnlock = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');

final _GetSystemTimes = _kernel32.lookupFunction<
    Int32 Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
    int Function(Pointer<Uint64>, Pointer<Uint64>,
        Pointer<Uint64>)>('GetSystemTimes');

final _GetProcessTimes = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>,
        Pointer<Uint64>),
    int Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>,
        Pointer<Uint64>)>('GetProcessTimes');

final _K32GetProcessMemoryInfo = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>, Uint32),
    int Function(int, Pointer<Uint8>, int)>('K32GetProcessMemoryInfo');

final _GlobalMemoryStatusEx = _kernel32.lookupFunction<
    Int32 Function(Pointer<Uint8>),
    int Function(Pointer<Uint8>)>('GlobalMemoryStatusEx');

final _GetCurrentProcess = _kernel32
    .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');

final _GetCurrentProcessId = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

const _inputSize = 40; // sizeof(INPUT) on x64

const _mouseButtons = {
  'left': (down: 0x0002, up: 0x0004, vk: 0x01),
  'right': (down: 0x0008, up: 0x0010, vk: 0x02),
  'middle': (down: 0x0020, up: 0x0040, vk: 0x04),
};
