// ignore_for_file: avoid_print
// Manual check of window-under-cursor and layout-aware characters.
// Run: dart run tool/smoke2.dart
import 'package:smart_clicker/platform/backend.dart';

void main() {
  final b = createBackend();
  final p = b.cursorPos();
  final w = b.windowAt(p.x, p.y);
  print('under cursor: ${w?.process} | "${w?.title}" shell=${w?.isShell}');
  final s = b.screenSize();
  final t = b.windowAt(s.w ~/ 2, s.h - 5);
  print('bottom centre (taskbar?): ${t?.process} | "${t?.title}" shell=${t?.isShell}');
  final a = b.activeWindow();
  print('active: ${a?.process} | "${a?.title}"');
  print('G key -> ${b.charForVk(0x47, shift: false)} / shift: ${b.charForVk(0x47, shift: true)}');
  print('1 key -> ${b.charForVk(0x31, shift: false)} / shift: ${b.charForVk(0x31, shift: true)}');
  print('enter -> ${b.charForVk(0x0D, shift: false)}  space -> "${b.charForVk(0x20, shift: false)}"');
}
