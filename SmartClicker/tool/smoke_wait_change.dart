// Live check of wait_change / wait_still on the real screen, without touching
// the mouse or the keyboard: a small area of the screen is watched. The script
// does nothing on its own (test mode). Run: dart run tool/smoke_wait_change.dart

import 'dart:io';
import 'dart:math';

import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

Future<void> main() async {
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(
      WindowsBackend(),
      {
        'main': 'smoke',
        'dryRun': true,
        'source': '''
let t0 = now()
let still = wait_still(0, 0, 300, 200, still: 700, timeout: 10s)
log("wait_still:", still, now() - t0, "мс")
let t1 = now()
let changed = wait_change(0, 0, 300, 200, timeout: 1500)
log("wait_change (на неподвижном месте — ждём false):", changed, now() - t1, "мс")
''',
      },
      events.add,
      random: Random(1));
  final r = await rt.runMain();
  for (final e in events.where((e) => e['t'] == 'log')) {
    stdout.writeln(e['m']);
  }
  stdout.writeln('статус: ${r['status']} ${r['error'] ?? ''}');
  exit(r['status'] == 'ok' ? 0 : 1);
}
