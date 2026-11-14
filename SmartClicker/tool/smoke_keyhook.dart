// Checks the hotkey hook on the real Windows with harmless keys (F23, F24):
// a held-back key must not reach the system, other keys and our own
// SendInput must pass; the mouse moved by the user is told from the mouse
// moved by a script.   dart run tool/smoke_keyhook.dart
// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _keybd = _user32.lookupFunction<Void Function(Uint8, Uint8, Uint32, IntPtr),
    void Function(int, int, int, int)>('keybd_event');
final _async = _user32
    .lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');

const f23 = 0x86, f24 = 0x87;

bool systemSees(int vk) => (_async(vk) & 0x8000) != 0;

/// keybd_event without our tag: for the hook it is a key of the user.
void foreign(int vk, bool down) => _keybd(vk, 0, down ? 0 : 2, 0);

final _mouseEvent = _user32.lookupFunction<Void Function(Uint32, Int32, Int32, Uint32, IntPtr),
    void Function(int, int, int, int, int)>('mouse_event');

/// mouse_event without our tag: for the hook it is the user's hand.
void userMoveBy(int dx, int dy) => _mouseEvent(0x0001, dx, dy, 0, 0);

Future<void> main() async {
  // Like the app (its manifest): physical pixels everywhere, also at 150%.
  _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetProcessDpiAwarenessContext')(-4);
  final b = WindowsBackend();
  var ok = true;
  void check(String what, bool cond) {
    print('${cond ? 'OK  ' : 'FAIL'} $what');
    ok &= cond;
  }

  b.holdBackKeys([
    [f24]
  ]);
  // The hook isolate starts asynchronously.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  check('hook installed', b.holdBackKeys([[f24]]));

  final sw = Stopwatch()..start();
  foreign(f24, true);
  final ms = sw.elapsedMicroseconds / 1000;
  await Future<void>.delayed(const Duration(milliseconds: 50));
  check('held-back F24: the system does not see it', !systemSees(f24));
  check('held-back F24: the program sees it (isVkDown)', b.isVkDown(f24));
  foreign(f24, false);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  check('held-back F24 released', !b.isVkDown(f24));
  print('     keybd_event through the hook took ${ms.toStringAsFixed(2)} ms');

  foreign(f23, true);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  check('other key F23 passes', systemSees(f23));
  check('F23 pressed by the user is counted as a user key', b.isUserKeyDown(f23));
  foreign(f23, false);

  b.keyEvent('f24', true); // our own SendInput (a script pressing F24)
  await Future<void>.delayed(const Duration(milliseconds: 50));
  check('our own SendInput of F24 passes', systemSees(f24));
  check('F24 pressed by a script is not counted as a user key', !b.isUserKeyDown(f24));
  b.keyEvent('f24', false);

  b.holdBackKeys(const []);
  foreign(f24, true);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  check('empty list: F24 passes again', systemSees(f24));
  foreign(f24, false);

  // The mouse: the user's moves are remembered, the script's are not.
  final start = b.cursorPos();
  check('mouse watch on', b.watchUserMouse(true));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  userMoveBy(5, 0);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final u = b.lastUserMouse();
  final here = b.cursorPos();
  check('user move seen at ${u?.x},${u?.y} (cursor $here)',
      u != null && (u.x - here.x).abs() <= 2 && (u.y - here.y).abs() <= 2 && u.ageMs < 1000);
  b.moveTo(start.x - 40, start.y - 40); // a script move (SendInput + SetCursorPos)
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final s = b.lastUserMouse();
  check('script move is not counted as the user move', s != null && s.x == u!.x && s.y == u.y);
  b.watchUserMouse(false);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  check('mouse watch off forgets', b.lastUserMouse() == null);
  b.moveTo(start.x, start.y);

  b.stopKeyHook();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  print(ok ? 'ALL OK' : 'SOME CHECKS FAILED');
  exit(ok ? 0 : 1);
}
