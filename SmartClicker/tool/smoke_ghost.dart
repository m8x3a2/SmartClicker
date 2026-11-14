// Checks the "ghost" mode of a recording on the real Windows: the user's
// clicks and keys must reach no program while it is on, yet the program
// must still see them (isVkDown), and everything passes again once it is
// off. Clicks go only into a test window of its own (a PowerShell form).
//   dart run tool/smoke_ghost.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _keybd = _user32.lookupFunction<Void Function(Uint8, Uint8, Uint32, IntPtr),
    void Function(int, int, int, int)>('keybd_event');
final _mouseEvent = _user32.lookupFunction<Void Function(Uint32, Int32, Int32, Uint32, IntPtr),
    void Function(int, int, int, int, int)>('mouse_event');
final _async =
    _user32.lookupFunction<Int16 Function(Int32), int Function(int)>('GetAsyncKeyState');

const f23 = 0x86;
const title = 'SmartClicker ghost check';

/// Without our tag: for the hook these are the user's hand.
void userKey(int vk, bool down) => _keybd(vk, 0, down ? 0 : 2, 0);
void userLeft(bool down) => _mouseEvent(down ? 0x0002 : 0x0004, 0, 0, 0, 0);

Future<void> pause([int ms = 80]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> main() async {
  _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetProcessDpiAwarenessContext')(-4);
  final b = WindowsBackend();
  var ok = true;
  void check(String what, bool cond) {
    print('${cond ? 'OK  ' : 'FAIL'} $what');
    ok &= cond;
  }

  // The target: a small topmost form that prints every click it gets.
  final form = await Process.start('powershell', [
    '-NoProfile',
    '-Command',
    "Add-Type -AssemblyName System.Windows.Forms; "
        "\$f = New-Object Windows.Forms.Form; \$f.Text = '$title'; \$f.TopMost = \$true; "
        "\$f.StartPosition = 'Manual'; \$f.Location = '200,200'; \$f.Size = '360,240'; "
        "\$f.Add_MouseDown({ [Console]::Out.WriteLine('CLICK'); [Console]::Out.Flush() }); "
        "[void]\$f.ShowDialog()",
  ]);
  var clicks = 0;
  form.stdout.transform(utf8.decoder).listen((s) => clicks += 'CLICK'.allMatches(s).length);
  final back = b.cursorPos();
  try {
    var target = b.windows().where((w) => w.title == title).firstOrNull;
    for (var i = 0; i < 50 && target == null; i++) {
      await pause(200);
      target = b.windows().where((w) => w.title == title).firstOrNull;
    }
    check('test window opened', target != null);
    if (target == null) return;
    final r = b.clientRect(target.handle)!;
    b.moveTo(r.x + r.w ~/ 2, r.y + r.h ~/ 2);
    await pause(300);

    check('ghost on', b.setGhost(true));
    await pause(500); // the hook isolate starts and puts the mouse hook on
    userLeft(true);
    await pause();
    check('ghost: the button is seen by the program (isVkDown)', b.isVkDown(0x01));
    check('ghost: the system does not see the button', (_async(0x01) & 0x8000) == 0);
    userLeft(false);
    await pause();
    check('ghost: released', !b.isVkDown(0x01));
    userKey(f23, true);
    await pause();
    check('ghost: F23 is seen by the program', b.isVkDown(f23));
    check('ghost: the system does not see F23', (_async(f23) & 0x8000) == 0);
    userKey(f23, false);
    await pause(400);
    check('ghost: the test window got no click', clicks == 0);

    // Pressed in the ghost mode, released after it: the release is eaten too.
    userLeft(true);
    await pause();
    b.setGhost(false);
    await pause(200);
    userLeft(false);
    await pause(400);
    check('release after the ghost mode is eaten too (no half click)', clicks == 0);

    userLeft(true);
    await pause();
    userLeft(false);
    await pause(600);
    check('ghost off: the click reaches the window', clicks == 1);
    userKey(f23, true);
    await pause();
    check('ghost off: F23 passes', (_async(f23) & 0x8000) != 0);
    userKey(f23, false);
  } finally {
    b.setGhost(false);
    b.moveTo(back.x, back.y);
    form.kill();
    b.stopKeyHook();
  }
  print(ok ? 'ALL OK' : 'SOME CHECKS FAILED');
  exit(ok ? 0 : 1);
}
