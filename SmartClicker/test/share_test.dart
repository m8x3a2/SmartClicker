// "Share a script": what goes into the archive, reading it back (and an
// export of all scripts), dangerous commands, clashing names on import.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/lang/line_diff.dart';
import 'package:smart_clicker/core/lang/picture_refs.dart';
import 'package:smart_clicker/core/lang/script_refs.dart';
import 'package:smart_clicker/core/storage/share_pack.dart';
import 'package:smart_clicker/core/storage/zip.dart';

void main() {
  final scripts = {
    'Фарм/Главный': '''
use_window("Game")
click_image("кнопка")
let pic = "враг.png"
if (find_image(pic)) { run_script("Общее") }
wait_image("нет_такой")
run_script("Фарм/Бой")
''',
    'Общее': 'function heal() { key("4") }\nrun_script("Фарм/Главный")   // a loop of scripts',
    'Фарм/Бой': "click_image('удар')\nscreenshot(\"снимок\")",
    'Чужой': 'click_image("лишняя")',
  };
  final pictures = {'кнопка', 'враг', 'удар', 'лишняя'};
  Uint8List bytesOf(String p) => Uint8List.fromList(utf8.encode('png:$p'));

  test('имя скрипта в run_script: полное, по последней части, без учёта регистра', () {
    final names = ['Фарм/Бой', 'Бой', 'Общее'];
    expect(resolveScriptName('фарм/бой', names), 'Фарм/Бой');
    expect(resolveScriptName('Бой', names), 'Бой');
    expect(resolveScriptName('Общее.cks', names), 'Общее');
    expect(resolveScriptName('Нет', names), isNull);
    expect(resolveScriptName('Общее', ['Папка/Общее']), 'Папка/Общее');
    expect(renameScriptRefs("run_script('Бой')\nrun_script(\"фарм/бой\")\nlog(\"Бой\")", 'Фарм/Бой', 'Х'),
        "run_script('Х')\nrun_script(\"Х\")\nlog(\"Бой\")");
  });

  test('переименование скрипта: run_script получает полный новый путь', () {
    final before = ['Бой', 'Фарм/Главный', 'Общее/Бой2', 'Х'];
    var r = fixScriptRefs('run_script("Бой")\nlog("Бой")\nrun_script(\'бой.cks\')',
        {'Бой': 'Атака'}, before, ['Атака', 'Фарм/Главный', 'Общее/Бой2', 'Х']);
    expect(r.text, 'run_script("Атака")\nlog("Бой")\nrun_script(\'Атака\')');
    expect(r.changes.map((c) => (c.line, c.from, c.to, c.broken)),
        [(1, 'Бой', 'Атака', true), (3, 'бой.cks', 'Атака', true)]);

    // Moved into a folder: the short name still finds it, but gets the full
    // path too (another "Бой2" could appear later); the old path is broken.
    final after = ['Бой', 'Фарм/Главный', 'Архив/Бой2', 'Х'];
    r = fixScriptRefs('run_script("Бой2")\nrun_script("Общее/Бой2")',
        {'Общее/Бой2': 'Архив/Бой2'}, before, after);
    expect(r.text, 'run_script("Архив/Бой2")\nrun_script("Архив/Бой2")');
    expect(r.changes.map((c) => c.broken), [false, true]);

    // Only the chosen changes.
    r = fixScriptRefs('run_script("Бой2")\nrun_script("Общее/Бой2")',
        {'Общее/Бой2': 'Архив/Бой2'}, before, after, only: (c) => c.line == 2);
    expect(r.text, 'run_script("Бой2")\nrun_script("Архив/Бой2")');

    // Other scripts are not touched.
    r = fixScriptRefs('run_script("Х")', {'Бой': 'Х2'}, before, ['Х2', 'Фарм/Главный', 'Общее/Бой2', 'Х']);
    expect(r.changes, isEmpty);
  });

  test('короткое имя, подходящее к нескольким скриптам', () {
    const names = ['night 2', 'temp/night 2', 'old/Night 2', 'Фарм/Бой'];
    expect(ambiguousScriptName('night 2', names), ['night 2', 'temp/night 2', 'old/Night 2']);
    expect(ambiguousScriptName('temp/night 2', names), isEmpty);
    expect(ambiguousScriptName('Бой', names), isEmpty);
  });

  test('в архив попадают вызываемые скрипты и картинки, которых нет — отдельно', () {
    final plan = planShare('Фарм/Главный', scripts,
        pictureExists: pictures.contains, pictureReaders: pictureReaders);
    expect(plan.scripts, ['Фарм/Главный', 'Общее', 'Фарм/Бой']);
    expect(plan.pictures, ['кнопка', 'враг', 'удар']);
    expect(plan.missing, ['нет_такой']); // "снимок" is made by screenshot
  });

  test('архив читается обратно; экспорт всех скриптов — тоже', () {
    final plan = planShare('Фарм/Главный', scripts,
        pictureExists: pictures.contains, pictureReaders: pictureReaders);
    final a = readShare(encodeShare(plan, scripts, bytesOf));
    expect(a.main, 'Фарм/Главный');
    expect(a.scripts.keys, ['Фарм/Главный', 'Общее', 'Фарм/Бой']);
    expect(a.scripts['Фарм/Бой'], scripts['Фарм/Бой']);
    expect(a.pictures.keys.toSet(), {'кнопка', 'враг', 'удар'});
    expect(utf8.decode(a.pictures['враг']!), 'png:враг');

    final legacy = readShare(zipEncode({
      'Общее.cks': utf8.encode('log(1)'),
      'Папка/Скрипт.cks': utf8.encode('log(2)'),
      'files/x.png': [1, 2, 3], // not a shared archive: pictures are not taken
      '../зло.cks': utf8.encode('log(3)'),
    }));
    expect(legacy.main, isNull);
    expect(legacy.scripts.keys.toSet(), {'Общее', 'Папка/Скрипт', 'зло'});
    expect(legacy.pictures, isEmpty);
  });

  test('опасные команды находятся с номером строки', () {
    final d = findDangers('Х', '''
log("run_command в тексте не считается")
run_command("del /q C:\\\\x")
if (true) { systemPower("shutdown") }
launch("notepad.exe")
write_file("a.txt", "1")
''');
    expect(d.map((e) => '${e.line} ${e.command}'),
        ['2 run_command', '3 system_power', '4 launch', '5 write_file']);
    expect(d.first.code, startsWith('run_command('));
    // A script that does not parse is checked by its text.
    expect(findDangers('Х', 'kill_process("game.exe"\n').single.command, 'kill_process');
  });

  test('импорт: новые, такие же и занятые имена; ссылки чинятся у переименованных', () {
    final archive = ShareArchive('Фарм/Главный', {
      'Фарм/Главный': 'click_image("кнопка")\nrun_script("Общее")\nrun_script("Фарм/Бой")',
      'Общее': 'log(1)',
      'Фарм/Бой': 'click_image("удар.png")',
    }, {
      'кнопка': bytesOf('кнопка'),
      'удар': bytesOf('удар'),
    });
    final mine = {'Общее': 'log(1)\n', 'Фарм/Бой': 'log("мой")'};
    final myPics = {'удар': bytesOf('мой удар')};
    final plan = planImport(archive,
        existingScript: (n) => mine[n], existingPicture: (n) => myPics[n]);
    String row(ImportItem i) =>
        '${i.picture ? 'pic' : 'scr'} ${i.name} ${i.exists} ${i.same} ${i.action.name}';
    expect(plan.items.map(row), [
      'scr Фарм/Главный false false add',
      'scr Общее true true skip',
      'scr Фарм/Бой true false rename',
      'pic кнопка false false add',
      'pic удар true false rename',
    ]);
    expect(plan.dangers, isEmpty);

    var out = resolveImport(plan);
    expect(out.scripts.keys, ['Фарм/Главный', 'Фарм/Бой (импорт)']);
    expect(out.scripts['Фарм/Главный'],
        'click_image("кнопка")\nrun_script("Общее")\nrun_script("Фарм/Бой (импорт)")');
    expect(out.scripts['Фарм/Бой (импорт)'], 'click_image("удар (импорт).png")');
    expect(out.pictures.keys, ['кнопка', 'удар (импорт)']);

    // "Keep mine": the imported script uses the existing one.
    plan.items[2].action = ImportAction.skip;
    out = resolveImport(plan);
    expect(out.scripts.keys, ['Фарм/Главный']);
    expect(out.scripts['Фарм/Главный'], contains('run_script("Фарм/Бой")'));
  });

  test('такой же скрипт, который запускает переименованный, добавляется копией', () {
    final archive = ShareArchive('Фарм', {
      'Фарм': 'run_script("Бой")',
      'Бой': 'log("бой")',
      'Лечение': 'click_image("зелье")',
    }, {
      'зелье': bytesOf('новое'),
    });
    final mine = {'Фарм': 'run_script("Бой")', 'Бой': 'log("мой бой")', 'Лечение': 'click_image("зелье")'};
    final plan = planImport(archive,
        existingScript: (n) => mine[n], existingPicture: (n) => n == 'зелье' ? bytesOf('старое') : null);
    final out = resolveImport(plan);
    expect(out.scripts, {
      'Фарм (импорт)': 'run_script("Бой (импорт)")',
      'Бой (импорт)': 'log("бой")',
      'Лечение (импорт)': 'click_image("зелье (импорт)")',
    });
    expect(out.copied, {'Фарм', 'Лечение'});
    expect(out.scriptNames['Фарм'], 'Фарм (импорт)');
  });

  test('свободное имя при импорте', () {
    final taken = {'a (импорт)', 'a (импорт 2)'};
    expect(importName('a', taken.contains), 'a (импорт 3)');
    expect(importName('b', taken.contains), 'b (импорт)');
  });

  test('различия строк: удалённые, добавленные, общие', () {
    String show(List<DiffLine> d) => d
        .map((l) => '${switch (l.kind) { DiffKind.same => ' ', DiffKind.removed => '-', DiffKind.added => '+' }}${l.text}')
        .join('|');
    expect(show(lineDiff('a\nb\nc\nd', 'a\nB\nc\nd\ne')), ' a|-b|+B| c| d|+e');
    expect(show(lineDiff('x', 'x')), ' x');
    expect(show(lineDiff('a\r\nb', 'a\nb')), ' a| b'); // Windows line ends
    expect(show(lineDiff('', 'new')), '-|+new');
    final d = lineDiff('1\n2\n3', '1\n3');
    expect(d.map((l) => (l.oldLine, l.newLine)), [(1, 1), (2, 0), (3, 2)]);
  });

  test('импорт: «заменить свой» пишет под тем же именем', () {
    final archive = ShareArchive('Бой', {'Бой': 'log("новый")'}, {});
    final plan = planImport(archive,
        existingScript: (n) => n == 'Бой' ? 'log("мой")' : null, existingPicture: (_) => null);
    expect(plan.mine('Бой'), 'log("мой")');
    plan.items.single.action = ImportAction.replace;
    expect(resolveImport(plan).scripts, {'Бой': 'log("новый")'});
  });
}
