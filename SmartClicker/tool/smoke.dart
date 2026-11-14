// ignore_for_file: avoid_print
// Manual smoke test of the real Windows backend (no clicks, no typing).
// Run: dart run tool/smoke.dart
import 'dart:io';

import 'package:smart_clicker/core/engine/runner.dart';
import 'package:smart_clicker/platform/backend.dart';

Future<void> main() async {
  final b = createBackend();
  print('backend: ${b.name}');
  print('screen: ${b.screenSize()}');
  final p = b.cursorPos();
  print('cursor: $p');
  print('pixel: ${b.pixel(p.x, p.y).toRadixString(16)}');
  final cap = b.capture(p.x, p.y, 2, 2);
  print('capture 2x2 bytes: ${cap.length} first=${cap.take(4).toList()}');
  b.moveTo(p.x, p.y);
  print('cursor after moveTo(same): ${b.cursorPos()}');
  final ws = b.windows();
  print('windows: ${ws.length}');
  for (final w in ws.take(5)) {
    print('  ${w.process} | ${w.title} | ${w.x},${w.y} ${w.w}x${w.h} client=${b.clientRect(w.handle)}');
  }
  final a = b.activeWindow();
  print('active: ${a?.process} | ${a?.title}');
  print('processes: ${b.processes().length}');
  print('battery: ${b.batteryLevel()} charging: ${b.isCharging()} net: ${b.networkConnected()}');
  print('clipboard length: ${b.getClipboard().length}');
  print('F12 down: ${b.isVkDown(0x7B)}');

  // Engine in a real isolate, test mode (nothing is clicked).
  final events = <Map<String, Object?>>[];
  var done = false;
  final runner = ScriptRunner((e) {
    events.add(e);
    if (e['t'] == 'done') done = true;
  });
  await runner.start({
    'main': 'smoke',
    'dryRun': true,
    'source': '''
log("screen", screen_size().w, "pixel", pixel(10, 10))
log("active", active_window().process, "windows", windows().length)
click(50%, 50%)
key("ctrl+c")
log("avg", avg_color(0, 0, 20, 20), "net", is_network_connected())
repeat { wait(50) }
''',
  });
  await Future<void>.delayed(const Duration(milliseconds: 700));
  runner.pause();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  runner.resume();
  runner.stop();
  while (!done) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  for (final e in events.where((e) => e['t'] != 'line')) {
    print('  event: $e');
  }

  // Hard kill of a script that never yields control voluntarily.
  done = false;
  events.clear();
  await runner.start({'main': 'hang', 'dryRun': true, 'source': 'while (true) { }'});
  await Future<void>.delayed(const Duration(milliseconds: 300));
  runner.kill();
  print('  hard kill: ${events.last}');
  exit(0);
}
