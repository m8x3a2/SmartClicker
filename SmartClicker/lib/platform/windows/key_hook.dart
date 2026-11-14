// Holding the program's hotkeys back from other programs: a WH_KEYBOARD_LL
// hook in its own isolate that eats presses completing one of our combos and
// tells keys held by the user from keys pressed by our scripts. On request
// the same isolate also watches where the USER moved the mouse (WH_MOUSE_LL)
// for the "mouse into a corner" stop.
part of 'windows_backend.dart';

// The hook lives in a separate isolate that does nothing but run its
// message loop. A hook in the window's thread would stall the keyboard of
// the whole system whenever the interface is busy for a moment.
//
// Both sides share one block of native memory:
const _khSize = 1024;
const _khDown = 0; // 256 bytes: 1 = key eaten by the hook and still down
const _khCount = 256; // number of combos below
const _khCombos = 260; // _khMaxCombos x 4 VK bytes (0 = unused)
const _khMaxCombos = 32;
const _khThread = 400; // Uint32: id of the hook thread (to stop it)
const _khStatus = 404; // Int32: 0 starting/stopped, 1 working, -1 failed
const _khUser = 512; // 256 bytes: 1 = held by the user (input without our tag)
const _khOwn = 768; // 256 bytes: 1 = held by our own SendInput (a script)
const _khMouseWanted = 420; // byte: 1 = the mouse hook should be on
const _khMouseSeen = 421; // byte: 1 = a move of the user was seen
const _khMouseX = 424; // Int32: where the user last moved the mouse
const _khMouseY = 428; // Int32
const _khMouseTick = 432; // Uint32: GetTickCount of that move

/// Thread message to the hook isolate: re-read [_khMouseWanted].
const _khMouseMsg = 0x8007; // WM_APP + 7

/// dwExtraInfo of our own SendInput events: the hook lets them through,
/// so a script can press F12 in a browser.
const _ownInputTag = 0x534D434B;

/// Shared memory as seen from the hook isolate.
Pointer<Uint8> _kh = nullptr;

void _keyHookMain(int address) {
  _kh = Pointer<Uint8>.fromAddress(address);
  final status = Pointer<Int32>.fromAddress(address + _khStatus);
  final msg = calloc<Uint8>(64);
  // The thread needs a message queue before anyone posts WM_QUIT to it.
  _PeekMessageW(msg, 0, 0, 0, 0);
  Pointer<Uint32>.fromAddress(address + _khThread).value =
      _GetCurrentThreadId();
  final proc = NativeCallable<_HookProc>.isolateLocal(
    _keyHook,
    exceptionalReturn: 0,
  );
  final hook = _SetWindowsHookExW(
    13,
    proc.nativeFunction,
    _GetModuleHandleW(nullptr),
    0,
  );
  if (hook == 0) {
    status.value = -1;
  } else {
    status.value = 1;
    _syncMouseHook();
    // The isolate never returns to its event loop: it stays on this thread,
    // and the hooks are called from inside GetMessageW.
    while (_GetMessageW(msg, 0, 0, 0) > 0) {
      if (Pointer<Uint32>.fromAddress(msg.address + 8).value == _khMouseMsg) {
        _syncMouseHook();
      }
    }
    _UnhookWindowsHookEx(hook);
    _kh[_khMouseWanted] = 0;
    _syncMouseHook();
    status.value = 0;
  }
  proc.close();
  calloc.free(msg);
}

int _mouseHookHandle = 0;
NativeCallable<_HookProc>? _mouseHookProc;

/// Puts the mouse hook on or off as [_khMouseWanted] says (hook isolate).
void _syncMouseHook() {
  final want = _kh[_khMouseWanted] != 0;
  if (want && _mouseHookHandle == 0) {
    final proc = NativeCallable<_HookProc>.isolateLocal(_userMouseHook, exceptionalReturn: 0);
    _mouseHookHandle = _SetWindowsHookExW(14, proc.nativeFunction, _GetModuleHandleW(nullptr), 0);
    if (_mouseHookHandle == 0) {
      proc.close();
    } else {
      _mouseHookProc = proc;
    }
  } else if (!want && _mouseHookHandle != 0) {
    _UnhookWindowsHookEx(_mouseHookHandle);
    _mouseHookHandle = 0;
    _mouseHookProc?.close();
    _mouseHookProc = null;
    _kh[_khMouseSeen] = 0;
  }
}

/// Remembers where the user (not a script) last moved the mouse.
int _userMouseHook(int code, int wParam, int lParam) {
  if (code == 0 && wParam == 0x0200) {
    // MSLLHOOKSTRUCT: pt.x, pt.y, mouseData, flags, time, dwExtraInfo at 24.
    final extra = Pointer<IntPtr>.fromAddress(lParam + 24).value;
    if (extra != _ownInputTag) {
      final p = Pointer<Int32>.fromAddress(lParam);
      final base = _kh.address;
      Pointer<Int32>.fromAddress(base + _khMouseX).value = p[0];
      Pointer<Int32>.fromAddress(base + _khMouseY).value = p[1];
      Pointer<Uint32>.fromAddress(base + _khMouseTick).value = _GetTickCount();
      _kh[_khMouseSeen] = 1;
    }
  }
  return _CallNextHookEx(0, code, wParam, lParam);
}

bool _khIsDown(int vk) =>
    (_GetAsyncKeyState(vk) & 0x8000) != 0 ||
    (vk < 256 && _kh[_khDown + vk] != 0);

bool _khCompletes(int vk) {
  final n = _kh[_khCount];
  for (var i = 0; i < n && i < _khMaxCombos; i++) {
    final combo = <int>[
      for (var j = 0; j < 4; j++)
        if (_kh[_khCombos + i * 4 + j] != 0) _kh[_khCombos + i * 4 + j],
    ];
    if (completesCombo(vk, combo, _khIsDown)) return true;
  }
  return false;
}

/// Runs for every key event in the system, so it does as little as it can.
int _keyHook(int code, int wParam, int lParam) {
  if (code == 0) {
    final k = Pointer<Uint32>.fromAddress(lParam); // KBDLLHOOKSTRUCT
    final vk = k[0] & 0xFF;
    final up = (k[2] & 0x80) != 0; // LLKHF_UP
    final extra = Pointer<IntPtr>.fromAddress(lParam + 16).value;
    if (extra == _ownInputTag) {
      _kh[_khOwn + vk] = up ? 0 : 1;
    } else {
      _kh[_khUser + vk] = up ? 0 : 1;
      if (up) {
        // The release of an eaten press is eaten too.
        if (_kh[_khDown + vk] != 0) {
          _kh[_khDown + vk] = 0;
          return 1;
        }
      } else if (_kh[_khDown + vk] != 0 || _khCompletes(vk)) {
        _kh[_khDown + vk] = 1; // auto-repeat of a held hotkey is eaten as well
        return 1;
      }
    }
  }
  return _CallNextHookEx(0, code, wParam, lParam);
}

mixin _KeyHook implements PlatformBackend {
  Pointer<Uint8> _khBuf = nullptr;
  String _khLast = '';

  bool _physicallyDown(int vk);

  /// Generic Shift / Ctrl / Alt also mean their left and right keys (the
  /// hook only sees the sided ones).
  static List<int> _sides(int vk) => switch (vk) {
    0x10 => const [0x10, 0xA0, 0xA1],
    0x11 => const [0x11, 0xA2, 0xA3],
    0x12 => const [0x12, 0xA4, 0xA5],
    _ => [vk],
  };

  @override
  bool isUserKeyDown(int vk) {
    final b = _khBuf;
    if (b == nullptr || vk < 0 || vk > 255) return isVkDown(vk);
    final sides = _sides(vk);
    if (sides.any((v) => b[_khUser + v] != 0 || b[_khDown + v] != 0)) {
      return true;
    }
    // A key the hook did not see go down (it was held before the hook
    // started, or Windows dropped the hook) still counts unless a script
    // is holding it.
    return _physicallyDown(vk) && !sides.any((v) => b[_khOwn + v] != 0);
  }

  /// The key is held down, but the hook ate it (GetAsyncKeyState does not
  /// see eaten keys).
  bool _heldBack(int vk) =>
      _khBuf != nullptr && vk >= 0 && vk < 256 && _khBuf[_khDown + vk] != 0;

  @override
  bool holdBackKeys(List<List<int>> combos) {
    final list = [
      for (final c in combos)
        if (c.isNotEmpty &&
            c.length <= 4 &&
            c.every((v) => v > 0 && v < 256) &&
            mainKeyOf(c) != null)
          c,
    ].take(_khMaxCombos).toList();
    if (_khBuf == nullptr) {
      // The hook runs even with nothing to hold back: it also tells the
      // user's keys from the script's ones (isUserKeyDown).
      _khBuf = calloc<Uint8>(_khSize);
      final status = Pointer<Int32>.fromAddress(_khBuf.address + _khStatus);
      Isolate.spawn(
        _keyHookMain,
        _khBuf.address,
        debugName: 'key hook',
      ).catchError((Object _) {
        status.value = -1;
        return Isolate.current;
      });
    }
    final b = _khBuf;
    final key = list.map((c) => c.join('+')).join(',');
    if (key != _khLast) {
      _khLast = key;
      b[_khCount] = 0; // the hook skips the table while it is being written
      for (var i = 0; i < list.length; i++) {
        for (var j = 0; j < 4; j++) {
          b[_khCombos + i * 4 + j] = j < list[i].length ? list[i][j] : 0;
        }
      }
      b[_khCount] = list.length;
    }
    return Pointer<Int32>.fromAddress(b.address + _khStatus).value != -1;
  }

  @override
  bool watchUserMouse(bool on) {
    if (_khBuf == nullptr) holdBackKeys(const []); // starts the hook isolate
    final b = _khBuf;
    final want = on ? 1 : 0;
    if (b[_khMouseWanted] != want) {
      b[_khMouseWanted] = want;
      final thread = Pointer<Uint32>.fromAddress(b.address + _khThread).value;
      // Not started yet: the isolate reads the flag itself once it is up.
      if (thread != 0) _PostThreadMessageW(thread, _khMouseMsg, 0, 0);
    }
    return Pointer<Int32>.fromAddress(b.address + _khStatus).value != -1;
  }

  @override
  ({int x, int y, int ageMs})? lastUserMouse() {
    final b = _khBuf;
    if (b == nullptr || b[_khMouseSeen] == 0) return null;
    final at = Pointer<Uint32>.fromAddress(b.address + _khMouseTick).value;
    return (
      x: Pointer<Int32>.fromAddress(b.address + _khMouseX).value,
      y: Pointer<Int32>.fromAddress(b.address + _khMouseY).value,
      ageMs: (_GetTickCount() - at) & 0xFFFFFFFF,
    );
  }

  @override
  void stopKeyHook() {
    final b = _khBuf;
    if (b == nullptr) return;
    b[_khCount] = 0;
    final thread = Pointer<Uint32>.fromAddress(b.address + _khThread).value;
    if (thread != 0) _PostThreadMessageW(thread, 0x0012, 0, 0); // WM_QUIT
    // The memory is not freed: the hook isolate may still be reading it.
    _khBuf = nullptr;
    _khLast = '';
  }
}
