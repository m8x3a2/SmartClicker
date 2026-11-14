// ignore_for_file: avoid_print
// Live check of type() into the Windows 11 Notepad: opens a new tab (in the
// user's Notepad window, if it is open), types a text inside with_window,
// at once switches to another window (as a script that clicks elsewhere
// would), then copies the tab text and compares. It types and erases only
// in a tab named "Без имени" (new) or by the test text itself; the clipboard
// is restored.
// Run: dart run tool/smoke_type.dart [rounds] [delay] [wait after type] [stay|switch] [keys]
// keys: digits pressed one by one with key("1") instead of type().
import 'dart:io';

import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/backend.dart';

const typed = 'Zx7 Привет, мир! Hello 1234567890 ёЁ';
const digits = '1234567890123456789012345678901234567890';

Future<void> main(List<String> args) async {
  final rounds = args.isEmpty ? 5 : int.parse(args[0]);
  final delay = args.length > 1 ? ', delay: ${args[1]}' : '';
  final after = args.length > 2 ? 'wait(${args[2]})' : '';
  // "stay": the script does not switch to another window after typing.
  final stay = args.length > 3 && args[3] == 'stay';
  final keys = args.length > 4 && args[4] == 'keys';
  final text = keys ? digits : typed;
  final input = keys
      ? [for (final ch in digits.split('')) 'key("$ch")'].join('\n    ')
      : 'type("$text"$delay)';
  final b = createBackend();
  final clip = b.getClipboard();
  final cover = b.activeWindow();
  Future<String> run(String source) async {
    final logs = <String>[];
    final rt = ScriptRuntime(b, {'main': 'smoke', 'source': source}, (e) {
      if (e['t'] == 'log' && e['lv'] == 'info') logs.add('${e['m']}');
    });
    final r = await rt.runMain();
    if (r['error'] != null) throw StateError('${r['error']}');
    return logs.isEmpty ? '' : logs.last;
  }

  // Only our own tab: a new empty one, or one that already holds the test text.
  bool ours() {
    final t = b.activeWindow()?.title ?? '';
    return t.startsWith('Без имени') || t.startsWith('*Z') || t.startsWith('*1');
  }

  await Process.start('notepad.exe', [], mode: ProcessStartMode.detached); // new tab
  await Future<void>.delayed(const Duration(seconds: 2));
  final note = b.windows().where((w) => w.process.toLowerCase() == 'notepad.exe' && w.w > 100).first;
  b.focusWindow(note.handle);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ours()) {
    print('Активна не новая вкладка ("${b.activeWindow()?.title}") — проверка остановлена');
    exit(1);
  }
  var ok = 0;
  try {
    for (var i = 0; i < rounds; i++) {
      if (!ours()) throw StateError('вкладка сменилась: ${b.activeWindow()?.title}');
      await run('''
with_window("notepad") {
    key("ctrl+a")
    key("delete")
    click(50%, 50%)
    $input
    $after
}
${stay ? 'wait(1000)' : 'focus_window("${cover?.process ?? 'explorer'}")'}
''');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      b.setClipboard('');
      final got = await run('''
with_window("notepad") {
    key("ctrl+a")
    key("ctrl+c")
    key("end")
}
wait(300)
log(get_clipboard())
''');
      final same = got.replaceAll('\r', '') == text;
      if (same) ok++;
      print('${same ? 'OK  ' : 'FAIL'} "$got"');
    }
    print('итог: $ok из $rounds');
    if (ours()) await run('with_window("notepad") {\n    key("ctrl+a")\n    key("delete")\n}');
  } finally {
    b.setClipboard(clip);
    if (cover != null) b.focusWindow(cover.handle);
  }
  exit(0);
}
