// Clipboard from scripts: the history of the «Буфер» page (clip_history,
// paste_clip, copy_clip) and the script's own stack (clip_add, paste_next,
// paste_all).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_clipscript_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  final sep = Platform.pathSeparator;

  Future<(StubBackend, List<String>, Map<String, Object?>)> run(String source, {bool dry = false}) async {
    final b = StubBackend();
    final events = <Map<String, Object?>>[];
    final rt = ScriptRuntime(
        b,
        {
          'main': 't',
          'source': source,
          'clipDir': '${tmp.path}${sep}clipboard',
          'filesDir': '${tmp.path}${sep}files',
          'dryRun': dry,
        },
        events.add,
        random: Random(1));
    final r = await rt.runMain();
    return (b, [for (final e in events) if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}'], r);
  }

  void history(List<Map<String, Object?>> items) {
    Directory('${tmp.path}${sep}clipboard').createSync(recursive: true);
    File('${tmp.path}${sep}clipboard${sep}index.json')
        .writeAsStringSync(jsonEncode({'items': items, 'trash': []}));
  }

  int pastes(StubBackend b) => b.calls.where((c) => c == 'keydown v').length;

  test('clip_history и paste_clip / copy_clip', () async {
    history([
      {'id': 'b', 'kind': 'text', 'text': 'второе', 'bytes': 6, 'at': '2026-11-16T10:00:00'},
      {'id': 'a', 'kind': 'files', 'files': [r'C:\a.txt'], 'bytes': 0, 'at': '2026-11-16T09:00:00'},
    ]);
    final (b, logs, r) = await run('''
let h = clip_history()
log(len(h), h[0].n, h[0].kind, h[0].text, h[1].kind, h[1].files[0])
paste_clip(1)
copy_clip(2)
''');
    expect(r['error'], isNull, reason: '$r');
    expect(logs, [r'2 1 text второе files C:\a.txt']);
    expect(pastes(b), 1, reason: 'copy_clip не вставляет');
    expect(b.clipData.files, [r'C:\a.txt']);

    final (_, _, bad) = await run('paste_clip(5)');
    expect('${bad['error']}', contains('2 записей'));
  });

  test('пустая история — понятная ошибка', () async {
    final (_, _, r) = await run('paste_clip()');
    expect('${r['error']}', contains('история буфера пуста'));
  });

  test('стопка: paste_next вставляет по порядку, paste_all — разом', () async {
    final (b, logs, r) = await run('''
clip_add("первый")
clip_add("второй")
paste_next()
let a = get_clipboard()
paste_next()
let c = get_clipboard()
log(a, c, paste_next(), clip_count())
clip_add("x")
clip_add("y")
paste_all(separator: ", ")
log(get_clipboard(), clip_count())
''');
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['первый второй false 0', 'x, y 0']);
    expect(pastes(b), 3);
  });

  test('стопка с файлом — всё одним списком файлов; нет файла — ошибка', () async {
    Directory('${tmp.path}${sep}files').createSync(recursive: true);
    File([tmp.path, 'files', 'снимок.png'].join(sep)).writeAsBytesSync([1, 2, 3]);
    final (b, _, r) = await run('''
clip_add_file("снимок.png")
clip_add("подпись")
paste_all()
''');
    expect(r['error'], isNull, reason: '$r');
    final files = b.clipData.files!;
    expect(files.first, endsWith('снимок.png'));
    expect(files.last, endsWith('.txt'));
    expect(File(files.last).readAsStringSync(), 'подпись');

    final (_, _, bad) = await run('clip_add_file("нет.png")');
    expect('${bad['error']}', contains('нет файла'));
  });

  test('тестовый режим: в буфер ничего не кладётся, стопка всё равно идёт дальше', () async {
    final (b, logs, r) = await run('''
clip_add("a")
log(paste_next(), clip_count())
''', dry: true);
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['true 0']);
    expect(pastes(b), 0);
    expect(b.clipData.text, isNull);
  });
}
