// Live check of find_images on the real screen, without the mouse or the
// keyboard. Without a sample: saves the bottom strip of the screen (the
// taskbar) to <folder>/полоса.png to pick a sample. With a sample x y w h:
// cuts it out of the screen and lists every place where it is.
// Run: dart run tool/smoke_find_images.dart <folder> [x y w h]

import 'dart:io';
import 'dart:math';

import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('dart run tool/smoke_find_images.dart <папка> [x y w h]');
    exit(2);
  }
  final source = args.length < 5
      ? '''
let s = screen_size()
log("экран:", s.w, s.h)
screenshot("полоса", 0, s.h - 60, s.w, 60)
log("полоса снята: y от", s.h - 60)
'''
      : '''
screenshot("экран")
screenshot("образец", ${args[1]}, ${args[2]}, ${args[3]}, ${args[4]})
let t0 = now()
let all = find_images("образец")
log("найдено:", len(all), "за", now() - t0, "мс")
for (p in all) { log("  ", p.left, p.top, p.w, "x", p.h) }
let t1 = now()
let scaled = find_images("образец", scale: "auto")
log("с масштабом:", len(scaled), "за", now() - t1, "мс")
log("max 2:", len(find_images("образец", max: 2)))
''';
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(
      WindowsBackend(),
      {'main': 'smoke', 'dryRun': true, 'filesDir': args[0], 'source': source},
      events.add,
      random: Random(1));
  final r = await rt.runMain();
  for (final e in events.where((e) => e['t'] == 'log')) {
    stdout.writeln(e['m']);
  }
  stdout.writeln('статус: ${r['status']} ${r['error'] ?? ''}');
  exit(r['status'] == 'ok' ? 0 : 1);
}
