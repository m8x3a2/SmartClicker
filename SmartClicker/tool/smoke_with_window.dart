// ignore_for_file: avoid_print
// Live check of with_window / require_window(focus: true) on real Windows:
// starts Paint, puts the window that was active over it, and the script
// only MOVES the mouse inside the block (no clicks, no typing). Then the
// cursor goes back and Paint is closed. Notepad is not used: on Windows 11
// it opens a tab in the user's own Notepad window.
// Run: dart run tool/smoke_with_window.dart
import 'dart:io';

import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/backend.dart';

Future<void> main() async {
  final b = createBackend();
  bool isPaint(String p) => p.toLowerCase() == 'mspaint.exe';
  if (b.processes().any(isPaint)) {
    print('Paint уже открыт — не трогаю его, проверка пропущена');
    exit(1);
  }
  final cursor = b.cursorPos();
  final cover = b.activeWindow();
  await Process.start('mspaint.exe', [], mode: ProcessStartMode.detached);
  try {
    for (var i = 0; i < 30 && !b.windows().any((w) => isPaint(w.process)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (cover != null) b.focusWindow(cover.handle);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    print('active before: ${b.activeWindow()?.process} (cover: ${cover?.process})');

    final logs = <String>[];
    final rt = ScriptRuntime(b, {
      'main': 'smoke',
      'source': '''
with_window("mspaint") {
    move(50%, 50%)
    log("in block: " + active_window().process)
}
log("after block")
''',
    }, (e) {
      if (e['t'] == 'log') logs.add('${e['m']}');
    });
    final r = await rt.runMain();
    print('result: ${r['status']} ${r['error'] ?? ''}');
    logs.forEach(print);
    // The real window, not a tiny "PopupHost" of the same program.
    final paint = b.windows().where((w) => isPaint(w.process)).toList()
      ..sort((a, b) => (b.w * b.h).compareTo(a.w * a.h));
    final rect = paint.isEmpty ? null : b.clientRect(paint.first.handle);
    final p = b.cursorPos();
    if (rect != null) {
      final cx = rect.x + rect.w ~/ 2, cy = rect.y + rect.h ~/ 2;
      print((p.x - cx).abs() <= 2 && (p.y - cy).abs() <= 2
          ? 'OK: курсор в центре окна Paint, Paint спереди: ${isPaint(b.activeWindow()?.process ?? '')}'
          : 'FAIL: курсор $p, центр Paint ($cx,$cy)');
    }
  } finally {
    b.moveTo(cursor.x, cursor.y);
    await Process.run('taskkill', ['/IM', 'mspaint.exe', '/F']);
    if (cover != null) b.focusWindow(cover.handle);
  }
  exit(0);
}
