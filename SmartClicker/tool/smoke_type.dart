// ignore_for_file: avoid_print
// Live check in a uniquely named temporary document. Every input checks its
// window handle, process and document title. Never closes Notepad or tabs.
// The clipboard text is restored; the temporary document is left open.
// Run: dart run tool/smoke_type.dart [rounds] [delay] [wait after type] [stay|switch] [keys|text] [text]
// keys: digits pressed one by one with key("1") instead of type().
import 'dart:io';
import 'dart:convert';

import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/backend.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

// Fail closed before every input action, including actions inside a script.
class SmokeBackend extends WindowsBackend {
  SmokeBackend(this.document);
  final String document;
  int? target;

  bool owns(WindowInfo? w) => w != null &&
      w.process.toLowerCase() == 'notepad.exe' &&
      (target == null || w.handle == target) &&
      w.title.replaceFirst(RegExp(r'^\*'), '').startsWith(document);

  void check() {
    if (!owns(activeWindow())) throw StateError('Тестовая вкладка не активна — ввод остановлен');
  }

  @override
  List<WindowInfo> windows() => super.windows().where((w) =>
      w.process.toLowerCase() != 'notepad.exe' || owns(w)).toList();

  @override
  void keyEvent(String key, bool down) {
    if (down) check();
    super.keyEvent(key, down);
  }

  @override
  void mouseButton(String button, bool down) {
    if (down) check();
    super.mouseButton(button, down);
  }

  @override
  void typeText(String text, {TypeMethod method = TypeMethod.auto}) {
    check();
    super.typeText(text, method: method);
  }
}

const typed = 'Zx7 Привет, мир! Hello 1234567890 ёЁ';
const digits = '1234567890123456789012345678901234567890';

Future<void> main(List<String> args) async {
  final rounds = args.isEmpty ? 5 : int.parse(args[0]);
  final delay = args.length > 1 ? ', delay: ${args[1]}' : '';
  final after = args.length > 2 ? 'wait(${args[2]})' : '';
  // "stay": the script does not switch to another window after typing.
  final stay = args.length > 3 && args[3] == 'stay';
  final keys = args.length > 4 && args[4] == 'keys';
  final text = keys ? digits : (args.length > 5 ? args[5] : typed);
  final input = keys
      ? [for (final ch in digits.split('')) 'key("$ch")'].join('\n    ')
      : 'type(${jsonEncode(text)}$delay)';
  final directory = await Directory.systemTemp.createTemp('smartclicker-smoke-');
  final name = 'smartclicker-${DateTime.now().microsecondsSinceEpoch}.txt';
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString('');
  final b = SmokeBackend(name);
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

  // Only the uniquely named document in the captured window.
  bool ours() {
    return b.owns(b.activeWindow());
  }

  await Process.start('notepad.exe', [file.path], mode: ProcessStartMode.detached);
  WindowInfo? note;
  for (var i = 0; i < 100 && note == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    note = b.windows().where(b.owns).firstOrNull;
  }
  if (note == null) throw StateError('Тестовый документ не открылся: ${file.path}');
  b.target = note.handle;
  if (!stay && (cover == null || cover.handle == note.handle)) {
    throw StateError('Для проверки переключения нужно другое исходное окно');
  }
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
      if (!stay && b.activeWindow()?.handle == note.handle) {
        throw StateError('Переключение с тестового окна не произошло');
      }
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
  print('Тестовый документ оставлен открытым: ${file.path}');
  exitCode = ok == rounds ? 0 : 1;
}
