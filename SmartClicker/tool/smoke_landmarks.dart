// Shows landmarks on the real screen for a moment and checks their colour
// and that clicks go through them.   dart run tool/smoke_landmarks.dart
// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';

import 'package:smart_clicker/platform/windows/windows_backend.dart';

Future<void> main() async {
  final user32 = DynamicLibrary.open('user32.dll');
  user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetProcessDpiAwarenessContext')(-4);
  final b = WindowsBackend();
  var ok = true;
  void check(String what, bool cond) {
    print('${cond ? 'OK  ' : 'FAIL'} $what');
    ok &= cond;
  }

  final s = b.screenSize();
  final p1 = (x: s.w ~/ 3, y: s.h ~/ 3), p2 = (x: s.w * 2 ~/ 3, y: s.h ~/ 2);
  const pink = 0xFF2BD6;
  final under = b.pidAt(p1.x, p1.y);
  b.showLandmarks([p1, p2], pink, 20);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  int diff(int a, int c) => [16, 8, 0].map((sh) => (((a >> sh) & 0xFF) - ((c >> sh) & 0xFF)).abs()).reduce((x, y) => x > y ? x : y);
  check('dot 1 is pink on the screen', diff(b.pixel(p1.x, p1.y), pink) < 12);
  check('dot 2 is pink on the screen', diff(b.pixel(p2.x, p2.y), pink) < 12);
  check('clicks go through (the window under it is the same)', b.pidAt(p1.x, p1.y) == under);
  b.showLandmarks([p2], 0x2FE05A, 20); // one less, another colour
  await Future<void>.delayed(const Duration(milliseconds: 300));
  check('dot 1 removed', diff(b.pixel(p1.x, p1.y), pink) >= 12);
  check('dot 2 green now', diff(b.pixel(p2.x, p2.y), 0x2FE05A) < 12);
  b.hideLandmarks();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  check('hidden', diff(b.pixel(p2.x, p2.y), 0x2FE05A) >= 12);
  print(ok ? 'ALL OK' : 'SOME CHECKS FAILED');
  exit(ok ? 0 : 1);
}
