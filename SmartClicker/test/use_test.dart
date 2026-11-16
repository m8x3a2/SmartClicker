// use("…"): functions of another script become available, its other code does
// not run; names, errors, lines and breakpoints belong to the right script.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/lang/checker.dart';
import 'package:smart_clicker/core/lang/completions.dart';
import 'package:smart_clicker/core/lang/script_refs.dart';
import 'package:smart_clicker/core/storage/share_pack.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

const _fight = '''
// library «Общее/бой»
let hits = 0
function attack(target) {
  hits++
  log("бью", target, hits)
}
function hits_count() { return hits }
function boom() {
  log("перед ошибкой")
  no_such_thing()
}
// a test of the library itself: must not run on use()
log("проверка библиотеки")
click(10, 10)
''';

Future<(List<String>, Map<String, Object?>, StubBackend, List<Map<String, Object?>>)> _run(String main,
    {Map<String, String> scripts = const {}, List<int> breaks = const []}) async {
  final b = StubBackend();
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(
      b, {'main': 'Главный', 'source': main, 'scripts': {'Главный': main, ...scripts}, 'breaks': breaks},
      events.add,
      random: Random(1));
  final r = await rt.runMain();
  final logs = [for (final e in events) if (e['t'] == 'log' && (e['lv'] == 'info' || e['lv'] == 'warn')) '${e['m']}'];
  return (logs, r, b, events);
}

void main() {
  test('подключаются функции и переменные библиотеки, остальной её код не выполняется', () async {
    final (logs, r, b, _) = await _run('''
log(use("бой"))
attack("волк")
attack("медведь")
log(hits_count())
''', scripts: {'Общее/бой': _fight});
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['3', 'бью волк 1', 'бью медведь 2', '2']);
    expect(b.calls.where((c) => c.startsWith('move') || c.startsWith('down')), isEmpty,
        reason: 'click в конце библиотеки не выполняется');
  });

  test('переменные библиотеки снаружи не видны; своя функция с тем же именем остаётся', () async {
    final (logs, r, _, _) = await _run('''
use("Общее/бой")
function attack(x) { log("своя", x) }
attack("волк")
log(hits)
''', scripts: {'Общее/бой': _fight});
    expect(logs.first, contains('attack'));
    expect(logs.first, contains('оставлены здешние'));
    expect(logs[1], 'своя волк');
    expect('${r['error']}', contains('hits'));
    expect(r['script'], isNull, reason: 'ошибка в главном скрипте');
  });

  test('ошибка внутри функции библиотеки — строка и имя библиотеки', () async {
    final (_, r, _, _) = await _run('use("бой")\n\n\nboom()', scripts: {'Общее/бой': _fight});
    expect(r['script'], 'Общее/бой');
    expect(r['line'], 10);
    expect('${r['error']}', contains('no_such_thing'));
  });

  test('функция главного скрипта, вызванная из библиотеки, — ошибка в главном', () async {
    final (_, r, _, _) = await _run('''
use("Общее/каждый")
for_each([1, 2], (x) => {
  if (x == 2) { missing_fn() }
})
''', scripts: {
      'Общее/каждый': 'function for_each(list, fn) {\n  for (x in list) { fn(x) }\n}',
    });
    expect(r['script'], isNull);
    expect(r['line'], 3);
  });

  test('точка останова главного скрипта не срабатывает на той же строке библиотеки', () async {
    // lines 2 and 3 of the library run inside attack(); the breakpoint is on
    // line 3 of the main script
    const main = 'use("бой")\nattack("x")\nlog("главный 3")';
    final events = <Map<String, Object?>>[];
    late ScriptRuntime rt;
    rt = ScriptRuntime(
        StubBackend(),
        {
          'main': 'Главный',
          'source': main,
          'scripts': {'Главный': main, 'бой': 'function attack(t) {\n  log("б2")\n  log("б3")\n}'},
          'breaks': [3],
        }, (e) {
      events.add(e);
      if (e['t'] == 'paused') rt.paused = false; // «Продолжить»
    }, random: Random(1));
    final r = await rt.runMain();
    expect(r['error'], isNull, reason: '$r');
    final order = [
      for (final e in events)
        if (e['t'] == 'paused') 'пауза ${e['l']}' else if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}',
    ];
    expect(order, ['б2', 'б3', 'пауза 3', 'главный 3']);
  });

  test('строки библиотеки не уходят в подсветку главного скрипта', () async {
    final (_, r, _, events) = await _run('use("бой")\nattack("x")\nwait(60)',
        scripts: {'Общее/бой': '\n\n\n\n\n\n\nfunction attack(t) {\n  wait(60)\n  log("x")\n}'});
    expect(r['error'], isNull, reason: '$r');
    final lines = {for (final e in events) if (e['t'] == 'line') e['l']};
    expect(lines.difference({1, 2, 3}), isEmpty, reason: 'строки 9–10 библиотеки не показываются: $lines');
  });

  test('библиотека подключает другую; круг не зацикливается; снаружи — только её функции', () async {
    final (logs, r, _, _) = await _run('''
use("А")
a()
log(type_of(b_only))
''', scripts: {
      'А': 'use("Б")\nfunction a() { log("a"); b() }',
      'Б': 'use("А")\nfunction b() { log("b") }\nfunction b_only() {}',
    });
    expect(r['error'], isNotNull, reason: 'b_only не подключалась в главный');
    expect(logs, ['a', 'b']);
  });

  test('нет такого скрипта, сам себя, круг через главный', () async {
    final (_, r1, _, _) = await _run('use("нет")');
    expect('${r1['error']}', contains('не найден'));
    final (_, r2, _, _) = await _run('use("Главный")');
    expect('${r2['error']}', contains('сам себя'));
    final (_, r3, _, _) = await _run('use("А")', scripts: {'А': 'use("Главный")\nfunction a() {}'});
    expect('${r3['error']}', contains('круг'));
    expect(r3['script'], 'А');
  });

  group('без запуска', () {
    final scripts = {
      'Общее/бой': _fight,
      'Общее/лечение': 'function heal() { key("q") }',
      'Фарм/лечение': 'function heal() { key("w") }',
    };
    String? source(String n) => scripts[resolveScriptName(n, scripts.keys)];
    List<String> issues(String src) => [
          for (final i in checkScript(
              src,
              CheckContext(
                builtins: AppController.builtinNames,
                scriptSource: source,
                imageExists: (_) => true,
                scriptNames: scripts.keys.toList(),
              )))
            '${i.line}: ${i.message}',
        ];

    test('проверка знает функции подключённого скрипта, но не его переменные', () {
      expect(issues('use("Общее/бой")\nattack("x")\nlog(hits_count())'), isEmpty);
      expect(issues('use("Общее/бой")\nlog(hits)').single, contains("'hits'"));
      expect(issues('attack("x")').single, contains("неизвестная функция 'attack'"));
      expect(issues('use("нет")').single, contains('скрипта "нет" нет'));
      expect(issues('use("лечение")\nheal()').single, contains('use("Общее/лечение")'),
          reason: 'короткое имя подходит двум скриптам — предупреждение');
    });

    test('подсказки редактора: функции подключённого скрипта', () {
      final found = usedFunctions('use("Общее/бой")\nat', source);
      expect([for (final c in found) c.signature], ['attack(target)', 'hits_count()', 'boom()']);
      expect(found.first.hint, contains('Общее/бой'));
      expect(suggest('att', found).first.name, 'attack');
      expect(usedFunctions('attack()', (_) => _fight), isEmpty);
    });

    test('переименование исправляет use, «Поделиться» берёт подключённый скрипт', () {
      final r = fixScriptRefs('use("бой")\nrun_script("бой")', {'Общее/бой': 'Игра/бой'},
          ['Общее/бой', 'Главный'], ['Игра/бой', 'Главный']);
      expect(r.text, 'use("Игра/бой")\nrun_script("Игра/бой")');
      final plan = planShare('Главный', {'Главный': 'use("Общее/бой")\nattack("x")', ...scripts},
          pictureExists: (_) => true);
      expect(plan.scripts, ['Главный', 'Общее/бой']);
    });
  });
}
