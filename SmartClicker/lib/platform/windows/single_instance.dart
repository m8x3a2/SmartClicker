// Win32 names are kept as-is for readability.
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _user32 = DynamicLibrary.open('user32.dll');

final _CreateMutexW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
    int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
final _OpenMutexW = _kernel32.lookupFunction<
    IntPtr Function(Uint32, Int32, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>)>('OpenMutexW');
final _CloseHandle =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _GetCurrentProcessId =
    _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');
final _GetTopWindow =
    _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetTopWindow');
final _GetWindow = _user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetWindow');
final _GetClassNameW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
final _GetWindowTextW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');
final _GetWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
final _IsIconic =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _IsWindowVisible =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
final _ShowWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final _SetForegroundWindow =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');

/// One copy of the program at a time: a named mutex lives as long as the
/// first copy. A second copy brings the window of the first one to the
/// front and quits (otherwise hotkeys would fire in both).
class SingleInstance {
  static const defaultName = r'Local\SmartClicker.SingleInstance';
  static int _handle = 0;

  /// True if no other copy runs. With [waitMs] the other copy is given
  /// that long to quit (restart as administrator).
  static bool acquire({String name = defaultName, int waitMs = 0}) {
    final n = name.toNativeUtf16();
    try {
      final deadline = DateTime.now().add(Duration(milliseconds: waitMs));
      while (true) {
        // An open mutex is another copy. NULL from CreateMutexW with the
        // name taken means the other copy runs with other rights (admin).
        final other = _OpenMutexW(0x00100000, 0, n); // SYNCHRONIZE
        if (other != 0) {
          _CloseHandle(other);
        } else {
          final h = _CreateMutexW(nullptr, 0, n);
          if (h != 0) {
            _handle = h;
            return true;
          }
        }
        if (DateTime.now().isAfter(deadline)) return false;
        sleep(const Duration(milliseconds: 100));
      }
    } finally {
      calloc.free(n);
    }
  }

  /// Lets another copy start (tests).
  static void release() {
    if (_handle != 0) _CloseHandle(_handle);
    _handle = 0;
  }

  /// Shows the window of the running copy, also when it is minimized or
  /// hidden in the tray. False if it was not found.
  static bool activateOther({String title = 'SmartClicker'}) {
    final me = _GetCurrentProcessId();
    final pid = calloc<Uint32>();
    final buf = calloc<Uint16>(128).cast<Utf16>();
    try {
      var hwnd = _GetTopWindow(0);
      for (var guard = 0; hwnd != 0 && guard < 10000; guard++) {
        _GetWindowThreadProcessId(hwnd, pid);
        if (pid.value != me &&
            _GetClassNameW(hwnd, buf, 128) > 0 &&
            buf.toDartString() == 'FLUTTER_RUNNER_WIN32_WINDOW' &&
            _GetWindowTextW(hwnd, buf, 128) > 0 &&
            buf.toDartString() == title) {
          if (_IsIconic(hwnd) != 0) {
            _ShowWindow(hwnd, 9); // SW_RESTORE
          } else if (_IsWindowVisible(hwnd) == 0) {
            _ShowWindow(hwnd, 5); // SW_SHOW
          }
          _SetForegroundWindow(hwnd);
          return true;
        }
        hwnd = _GetWindow(hwnd, 2); // GW_HWNDNEXT
      }
      return false;
    } finally {
      calloc.free(pid);
      calloc.free(buf);
    }
  }
}
