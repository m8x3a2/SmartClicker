import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/recorder/recorder.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/storage/zip.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/backend.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

class Run {
  final StubBackend backend;
  final List<Map<String, Object?>> events;
  final Map<String, Object?> result;
  Run(this.backend, this.events, this.result);

  List<String> get logs => events
      .where((e) => e['t'] == 'log' && e['lv'] == 'info')
      .map((e) => '${e['m']}')
      .toList();
  String get status => '${result['status']}';
}

Future<Run> run(String source,
    {Map<String, Object?> cfg = const {},
    StubBackend? backend,
    void Function(ScriptRuntime rt)? setup}) async {
  final b = backend ?? StubBackend();
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(b, {'main': 'test', 'source': source, ...cfg},
      events.add,
      random: Random(1));
  setup?.call(rt);
  final result = await rt.runMain();
  return Run(b, events, result);
}

Future<List<String>> out(String source) async {
  final r = await run(source);
  expect(r.result['error'], isNull, reason: '${r.result}');
  return r.logs;
}

void main() {
  group('язык', () {
    test('арифметика и переменные', () async {
      expect(await out('let x = 2 + 3 * 4\nx += 1\nlog(x, 10 / 4, 10 / 5, 7 % 3)'),
          ['15 2.5 2 1']);
    });

    test('строки и шаблоны', () async {
      expect(await out(r'''
let n = 3
log("a" + n, `n=${n + 1}!`, 'x'.toUpperCase(), "a,b".split(",").length)
'''), ['a3 n=4! X 2']);
    });

    test('if / else if / else', () async {
      expect(
          await out('let x = 5\nif (x > 10) { log("big") } else if (x > 3) { log("mid") } else { log("small") }'),
          ['mid']);
    });

    test('циклы: repeat, while, for, for-in, break, continue', () async {
      expect(await out('''
let s = 0
repeat (3) { s++ }
while (s < 5) { s += 1 }
for (let i = 0; i < 3; i++) { if (i == 1) continue; s += 10 }
for (i in 1..3) { s += i }
for (v of [100, 200]) { if (v == 200) break; s += v }
log(s)
'''), ['131']);
    });

    test('функции, рекурсия, стрелки, замыкания', () async {
      expect(await out('''
log(fact(5))
function fact(n) { return n <= 1 ? 1 : n * fact(n - 1) }
let add = (a, b) => a + b
let twice = x => { return x * 2 }
log(add(2, 3), twice(4), [1, 2, 3].map(x => x * 2).join("-"))
'''), ['120', '5 8 2-4-6']);
    });

    test('массивы и объекты', () async {
      expect(await out('''
let a = [1, 2]
a.push(3)
let o = {name: "A", n: 1}
o.n += 4
o["k"] = a.length
log(a, o.name, o.n, o.k, a.includes(2), keys(o).length)
'''), ['[1, 2, 3] A 5 3 true 3']);
    });

    test('switch и try/catch', () async {
      expect(await out('''
function kind(x) {
  switch (x) {
    case 1: return "one"
    case "a": return "letter"
    default: return "other"
  }
}
log(kind(1), kind("a"), kind(9))
try { throw "boom" } catch (e) { log("caught", e) } finally { log("fin") }
try { nope() } catch (e) { log("err") }
'''), ['one letter other', 'caught boom', 'fin', 'err']);
    });

    test('await/async игнорируются, console.log и Math работают', () async {
      expect(await out('''
async function f() { await wait(1); return Math.floor(3.7) }
console.log(await f())
'''), ['3']);
    });

    test('единицы времени, проценты и остаток от деления', () async {
      expect(await out('log(2s, 500ms, 1m, 10%3, 50%, 10 % 4)'),
          ['2000 500 60000 1 50% 2']);
    });

    test('ошибка содержит номер строки', () async {
      final r = await run('let a = 1\nlog(a)\nunknown_fn(1)\n');
      expect(r.status, 'error');
      expect(r.result['line'], 3);
      expect('${r.result['error']}', contains('unknown_fn'));
    });

    test('синтаксическая ошибка содержит номер строки', () async {
      final r = await run('log(1)\nif (x {\n}');
      expect(r.status, 'error');
      expect(r.result['line'], 2);
    });

    test('вызов с новой строки не склеивается с предыдущим выражением', () async {
      expect(await out('let a = 5\n(a > 1) ? log("y") : log("n")'), ['y']);
    });
  });

  group('движок', () {
    test('click переводит проценты в пиксели', () async {
      final r = await run('click(50%, 25%)\nclick(100, 200, button: "right")');
      expect(r.status, 'ok');
      expect(r.backend.calls, [
        'move 960,270', 'down left', 'up left', //
        'move 100,200', 'down right', 'up right', 'releaseAll'
      ].where((c) => c != 'releaseAll').toList());
    });

    test('use_window считает координаты от окна', () async {
      final b = StubBackend()
        ..windowList = [const WindowInfo(7, 'My Game', 'game.exe', 1, 100, 50, 800, 600)];
      final r = await run('use_window("game")\nclick(50%, 50%)\nclick(10, 10)', backend: b);
      expect(r.status, 'ok', reason: '${r.result}');
      expect(b.calls.where((c) => c.startsWith('move')), ['move 500,350', 'move 110,60']);
    });

    test('тестовый режим не выполняет ввод', () async {
      final r = await run('click(1, 1)\nkey("ctrl+c")\ntype("hi")', cfg: {'dryRun': true});
      expect(r.status, 'ok');
      expect(r.backend.calls, isEmpty);
    });

    test('key нажимает и отпускает сочетание в правильном порядке', () async {
      final r = await run('key("ctrl+shift+a")');
      expect(r.backend.calls, [
        'keydown ctrl', 'keydown shift', 'keydown a', //
        'keyup a', 'keyup shift', 'keyup ctrl'
      ]);
    });

    test('неизвестная клавиша — понятная ошибка', () async {
      final r = await run('key("ctrl+foo")');
      expect(r.status, 'error');
      expect('${r.result['error']}', contains('foo'));
    });

    test('drag зажимает, двигает и отпускает', () async {
      final r = await run('drag(0, 0, 100, 0, 40)');
      final c = r.backend.calls;
      expect(c.first, 'move 0,0');
      expect(c[1], 'down left');
      expect(c.last, 'up left');
      expect(c[c.length - 2], 'move 100,0');
    });

    test('зажатые клавиши отпускаются при ошибке', () async {
      final r = await run('key_down("shift")\nmouse_down(5, 5)\nfail_here()');
      expect(r.status, 'error');
      expect(r.backend.calls, containsAll(['keyup shift', 'up left']));
    });

    test('wait(диапазон) и пауза/стоп', () async {
      final sw = Stopwatch()..start();
      final r = await run('wait(30..60)\nlog("ok")');
      expect(r.logs, ['ok']);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(25));
    });

    test('стоп прерывает бесконечный цикл без wait', () async {
      final r = await run('while (true) { let x = 1 }', setup: (rt) {
        Future<void>.delayed(const Duration(milliseconds: 60), () => rt.stopRequested = true);
      });
      expect(r.status, 'stopped');
    });

    test('стоп прерывает долгий wait', () async {
      final sw = Stopwatch()..start();
      final r = await run('wait(60s)', setup: (rt) {
        Future<void>.delayed(const Duration(milliseconds: 50), () => rt.stopRequested = true);
      });
      expect(r.status, 'stopped');
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('лимит циклов', () async {
      final r = await run('repeat { }', cfg: {'maxLoops': 100});
      expect(r.status, 'limit');
    });

    test('exit() завершает скрипт успешно', () async {
      final r = await run('log("a")\nexit()\nlog("b")');
      expect(r.status, 'ok');
      expect(r.logs, ['a']);
    });

    test('пиксели', () async {
      final b = StubBackend()..pixelColor = 0xFF0000;
      final r = await run('''
log(pixel(1, 1), pixel_is(1, 1, "#FA0505"), pixel_is(1, 1, #00FF00))
log(wait_pixel(1, 1, "#00FF00", timeout: 50), avg_color(0, 0, 4, 4))
let p = find_color("#FF0000", 10, 20, 5, 5)
log(p.x, p.y)
''', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(r.logs, ['#FF0000 true false', 'false #FF0000', '10 20']);
    });

    test('run_script выполняет другой скрипт и делится функциями', () async {
      final r = await run('run_script("lib")\nlog(hello("мир"))', cfg: {
        'scripts': {'Lib': 'function hello(n) { return "привет, " + n }'}
      });
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(r.logs.last, 'привет, мир');
    });

    test('run_script находит скрипт в папке по имени и по пути', () async {
      final r = await run('run_script("util")\nrun_script("Игры/Util")\nlog(n)', cfg: {
        'scripts': {'Игры/Util': 'n = 1\nfunction helper() { return null }'}
      });
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(r.logs.last, '1');
    });

    test('launch не открывает вторую копию запущенной программы', () async {
      final b = StubBackend()
        ..windowList = [const WindowInfo(1, 'Doc', 'notepad.exe', 1, 0, 0, 10, 10)];
      final r = await run('log(launch("notepad.exe"), launch("C:/x/Notepad.exe"))',
          backend: b, cfg: {'dryRun': true});
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(r.logs.last, 'false false');
    });

    test('require_window ждёт активное окно', () async {
      final b = StubBackend();
      final r = await run('require_window("game")\nclick(1, 1)', backend: b, setup: (rt) {
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          b.active = const WindowInfo(1, 'Game', 'game.exe', 1, 0, 0, 10, 10);
        });
      });
      expect(r.status, 'ok');
      expect(b.calls, contains('down left'));
    });

    const game = WindowInfo(1, 'Game', 'game.exe', 1, 100, 100, 200, 100);
    const other = WindowInfo(2, 'Chat', 'chat.exe', 2, 0, 0, 50, 50);

    test('require_window выводит перекрытое окно вперёд (focus: true по умолчанию)', () async {
      final b = StubBackend()
        ..windowList = [game, other]
        ..active = other;
      final r = await run('require_window("game")\nclick(1, 1)', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      final focus = b.calls.indexOf('focus 1');
      expect(focus, greaterThanOrEqualTo(0));
      expect(b.calls.indexOf('down left'), greaterThan(focus));
    });

    test('require_window(focus: false) не трогает окна, а ждёт', () async {
      final b = StubBackend()
        ..windowList = [game, other]
        ..active = other;
      final r = await run('require_window("game", focus: false)\nclick(1, 1)', backend: b,
          setup: (rt) {
        Future<void>.delayed(const Duration(milliseconds: 300), () => b.active = game);
      });
      expect(r.status, 'ok');
      expect(b.calls, isNot(contains('focus 1')));
      expect(b.calls, contains('down left'));
    });

    test('require_window узнаёт окно, у которого сменился заголовок', () async {
      final b = StubBackend()
        ..windowList = [const WindowInfo(1, '*Новый — Блокнот', 'notepad.exe', 1, 0, 0, 9, 9), other]
        ..active = other;
      final r = await run('require_window("notepad|Отчёт")\nclick(1, 1)\nclick(2, 2)', backend: b);
      expect(r.status, 'ok', reason: '${r.result}');
      expect(b.calls.where((c) => c == 'down left').length, 2);
    });

    test('with_window: внутри блока — окно, после блока — как было', () async {
      final b = StubBackend()
        ..windowList = [game, other]
        ..active = other;
      final r = await run('''
with_window("game") {
    click(50%, 50%)
}
click(10, 10)
''', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      final calls = b.calls.where((c) => c.startsWith('move') || c.startsWith('focus')).toList();
      expect(calls, ['focus 1', 'move 200,150', 'move 10,10']);
    });

    test('with_window: после ошибки и break внутри блока привязка снимается', () async {
      final b = StubBackend()
        ..windowList = [game, other]
        ..active = game;
      final r = await run('''
try {
    with_window("game") { throw "x" }
} catch (e) { }
repeat {
    with_window("game") { break }
}
click(10, 10)
''', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(b.calls.where((c) => c.startsWith('move')).toList(), ['move 10,10']);
    });

    test('окно программы: крошечное всплывающее (PopupHost) не берётся, если есть настоящее', () async {
      final b = StubBackend()
        ..windowList = [
          const WindowInfo(7, 'PopupHost', 'notepad.exe', 3, 500, 225, 38, 47),
          const WindowInfo(8, 'Без имени — Блокнот', 'notepad.exe', 3, 100, 100, 800, 600),
        ];
      final r = await run('with_window("notepad") { move(50%, 50%) }', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(b.calls.where((c) => c.startsWith('move')), ['move 500,400']);
    });

    test('with_window: окна нет — понятная ошибка', () async {
      var r = await run('with_window("нет такого", timeout: 0) { click(1, 1) }');
      expect('${r.result['error']}', contains('with_window: окно "нет такого" не найдено'));
      r = await run('with_window("нет такого", timeout: 600) { click(1, 1) }');
      expect('${r.result['error']}', contains('не появилось за 0.6 с'));
    });

    test('with_window ждёт, пока окно появится', () async {
      final b = StubBackend()..windowList = [other];
      final r = await run('with_window("game") { click(50%, 50%) }', backend: b, setup: (rt) {
        Future<void>.delayed(const Duration(milliseconds: 300), () => b.windowList = [game, other]);
      });
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(b.calls, contains('move 200,150'));
    });

    test('with_window(restore: true) возвращает вперёд прежнее окно', () async {
      final b = StubBackend()
        ..windowList = [game, other]
        ..active = other;
      final r = await run('with_window("game", restore: true) { click(50%, 50%) }', backend: b);
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(b.calls.where((c) => c.startsWith('focus')), ['focus 1', 'focus 2']);
      expect(b.active, other);
    });
  });

  group('запись', () {
    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 30));
    Future<void> tap(StubBackend b, List<int> vks) async {
      for (final vk in vks) {
        b.downVks.add(vk);
        await tick();
      }
      for (final vk in vks.reversed) {
        b.downVks.remove(vk);
        await tick();
      }
    }

    test('текст, смена раскладки и сочетания', () async {
      final b = StubBackend()..chars.addAll({0x47: 'п', 0x48: 'р', 0x4B: 'k'});
      final rec = Recorder(b, () => false, {});
      rec.start();
      await tick();
      await tap(b, [0x47]); // г-клавиша в русской раскладке -> "п"
      await tap(b, [0x48]);
      await tap(b, [0x12, 0x10]); // Alt+Shift
      await tap(b, [0x4B]);
      await tap(b, [0x11, 0x41]); // Ctrl+A
      await tap(b, [0x0D]); // Enter
      final code = rec.stop(const RecordOptions());
      final lines = code.split('\n').where((l) => l.isNotEmpty && !l.startsWith('wait')).toList();
      expect(lines, ['type("пр")', 'key("alt+shift")', 'type("k")', 'key("ctrl+a")', 'key("enter")']);
    });

    test('без режима текста записываются клавиши', () async {
      final b = StubBackend()..chars[0x47] = 'п';
      final rec = Recorder(b, () => false, {});
      rec.start();
      await tick();
      await tap(b, [0x47]);
      expect(rec.stop(const RecordOptions(text: false)).trim(), 'key("g")');
    });
  });

  group('запись мыши', () {
    Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));
    Future<void> click(StubBackend b, int x, int y) async {
      b.cx = x;
      b.cy = y;
      await ms(40);
      b.downVks.add(0x01);
      await ms(40);
      b.downVks.remove(0x01);
      await ms(40);
    }

    List<String> code(String s) =>
        s.split('\n').where((l) => l.isNotEmpty && !l.startsWith('wait')).toList();

    test('режим остановок записывает наведение', () async {
      final b = StubBackend();
      final rec = Recorder(b, () => false, {});
      rec.start();
      await ms(30);
      b.cx = 100;
      b.cy = 120;
      await ms(350); // the cursor rests here
      await click(b, 500, 600);
      final lines = code(rec.stop(const RecordOptions(
          percent: false, mode: RecordMode.hover, dwellMs: 200)));
      expect(lines.length, 2, reason: '$lines');
      expect(lines[0], startsWith('move(100, 120'));
      expect(lines[1], 'click(500, 600)');
    });

    test('обычный режим не записывает движение', () async {
      final b = StubBackend();
      final rec = Recorder(b, () => false, {});
      rec.start();
      await ms(30);
      b.cx = 100;
      await ms(300);
      await click(b, 500, 600);
      expect(code(rec.stop(const RecordOptions(percent: false))),
          ['click(500, 600)']);
    });

    test('полная траектория записывается и воспроизводится', () async {
      final b = StubBackend();
      final rec = Recorder(b, () => false, {});
      rec.start();
      for (var i = 1; i <= 15; i++) {
        b.cx = i * 20;
        b.cy = i * 10;
        await ms(20);
      }
      await click(b, 400, 200);
      final src = rec.stop(const RecordOptions(mode: RecordMode.full));
      final lines = code(src);
      expect(lines.where((l) => l.startsWith('mouse_path(')).length,
          greaterThanOrEqualTo(2), reason: src);
      expect(lines.last, startsWith('click('));

      final r = await run(src);
      expect(r.result['error'], isNull, reason: '${r.result}\n$src');
      final movesMade = r.backend.calls.where((c) => c.startsWith('move')).toList();
      expect(movesMade.length, greaterThan(10));
      expect(movesMade.last, 'move 400,200');
      expect(r.backend.calls, contains('down left'));
    });

    test('привязка к окнам заменяет клик по панели задач на focus_window', () async {
      const taskbar = WindowInfo(1, '', 'explorer.exe', 9, 0, 1000, 1920, 80);
      const doc = WindowInfo(2, '*Doc — Блокнот', 'Notepad.exe', 5, 100, 100, 800, 600);
      const other = WindowInfo(3, 'Без имени — Блокнот', 'Notepad.exe', 5, 2000, 0, 10, 10);
      final b = StubBackend()..windowList = [taskbar, doc, other];
      final rec = Recorder(b, () => false, {});
      rec.start();
      await click(b, 500, 1040); // taskbar icon
      await click(b, 300, 350); // inside the document window
      final src =
          rec.stop(const RecordOptions(percent: false, window: true));
      expect(code(src), [
        'focus_window("Notepad.exe|Doc — Блокнот")',
        'use_window("Notepad.exe|Doc — Блокнот")',
        'require_window("Notepad.exe|Doc — Блокнот")',
        'click(200, 250)',
        'use_screen()',
        'require_window(null)',
      ]);

      // And the generated script really clicks inside that window.
      final r = await run(src, backend: StubBackend()..windowList = [taskbar, doc, other]);
      expect(r.result['error'], isNull, reason: '${r.result}');
      expect(r.backend.calls.where((c) => c.startsWith('move')), ['move 300,350']);
    });

    test('без привязки к окнам клики остаются экранными', () async {
      const taskbar = WindowInfo(1, '', 'explorer.exe', 9, 0, 1000, 1920, 80);
      final b = StubBackend()..windowList = [taskbar];
      final rec = Recorder(b, () => false, {});
      rec.start();
      await click(b, 500, 1040);
      expect(code(rec.stop(const RecordOptions(percent: false))),
          ['click(500, 1040)']);
    });
  });

  group('остановки курсора', () {
    Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));
    List<String> code(String s) =>
        s.split('\n').where((l) => l.isNotEmpty && !l.startsWith('wait')).toList();

    test('дрожание мыши не дробит остановку, остановки у клика пропускаются', () async {
      final b = StubBackend();
      final rec = Recorder(b, () => false, {});
      rec.start();
      await ms(30);
      // Rest around (100,100) with tremor for ~400 ms.
      for (var i = 0; i < 8; i++) {
        b.cx = 100 + i % 3;
        b.cy = 100 + i % 2;
        await ms(50);
      }
      // Go to the button, hesitate right on it, click, hesitate again.
      b.cx = 500;
      b.cy = 600;
      await ms(300);
      b.downVks.add(0x01);
      await ms(40);
      b.downVks.remove(0x01);
      await ms(40);
      b.cx = 503;
      b.cy = 604;
      await ms(300);
      final lines = code(rec.stop(const RecordOptions(
          percent: false, mode: RecordMode.hover, dwellMs: 200)));
      expect(lines.length, 2, reason: '$lines');
      expect(lines[0], startsWith('move(10'));
      expect(lines[1], 'click(500, 600)');
    });
  });

  test('запись колеса мыши: щелчки подряд склеиваются, своё окно пропускается', () async {
    Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));
    const ownPid = 77;
    const own = WindowInfo(1, 'SmartClicker', 'smart_clicker.exe', ownPid, 0, 0, 800, 600);
    final b = StubBackend()..windowList = [own];
    final rec = Recorder(b, () => false, {},
        overOwnWindow: (x, y) => b.pidAt(x, y) == ownPid);
    rec.start();
    expect(rec.wheelWatched, isTrue);
    await ms(30);
    for (var i = 0; i < 3; i++) {
      b.wheel!(-120, false, 1000, 700); // towards the user = down
      await ms(30);
    }
    b.wheel!(120, false, 1000, 700); // direction changed: a new command
    await ms(30);
    b.wheel!(-120, false, 100, 100); // over our own window: ignored
    await ms(700);
    b.wheel!(240, true, 1200, 700); // horizontal, two notches to the right
    await ms(30);
    final lines = rec
        .stop(const RecordOptions(percent: false))
        .split('\n')
        .where((l) => l.startsWith('scroll'))
        .toList();
    expect(lines, [
      'scroll(3, 1000, 700)',
      'scroll(-1, 1000, 700)',
      'scroll(2, 1200, 700, horizontal: true)',
    ]);
    expect(b.wheel, isNull);
  });

  test('запись не теряет клики вне нашего окна, пока оно ещё активно', () async {
    Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));
    const ownPid = 77;
    const own = WindowInfo(1, 'SmartClicker', 'smart_clicker.exe', ownPid, 0, 0, 800, 600);
    const taskbar = WindowInfo(2, '', 'explorer.exe', 9, 0, 1000, 1920, 80);
    final b = StubBackend()..windowList = [own, taskbar];
    // Our window stays the active one for the whole recording.
    final rec = Recorder(b, () => true, {},
        overOwnWindow: (x, y) => b.pidAt(x, y) == ownPid);
    Future<void> click(int x, int y) async {
      b.cx = x;
      b.cy = y;
      await ms(40);
      b.downVks.add(0x01);
      await ms(40);
      b.downVks.remove(0x01);
      await ms(40);
    }

    rec.start();
    b.cx = 900;
    b.cy = 1040;
    await ms(350); // hover over a taskbar icon
    await click(900, 1040); // click it
    await click(400, 300); // click inside our own window: ignored
    final lines = rec
        .stop(const RecordOptions(percent: false, mode: RecordMode.hover, dwellMs: 200))
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('wait'))
        .toList();
    expect(lines, ['click(900, 1040)']);

    // Without the click the hover itself must be kept.
    rec.start();
    b.cx = 1200;
    b.cy = 1040;
    await ms(350);
    b.cx = 100; // back over our window
    b.cy = 100;
    await ms(100);
    final hover = rec
        .stop(const RecordOptions(percent: false, mode: RecordMode.hover, dwellMs: 200))
        .trim();
    expect(hover, startsWith('move(1200, 1040'));
  });

  test('окно с изменившимся заголовком находится по программе', () async {
    final b = StubBackend()
      ..windowList = [const WindowInfo(7, '*99999 — Блокнот', 'Notepad.exe', 1, 100, 50, 800, 600)];
    final r = await run(
        'log(focus_window("Notepad.exe|как dela — Блокнот"))\n'
        'use_window("Notepad.exe|как dela — Блокнот")\nclick(10, 10)\n'
        'log(window_exists("Chrome.exe|x"))',
        backend: b);
    expect(r.result['error'], isNull, reason: '${r.result}');
    expect(r.logs.first, 'true');
    expect(r.logs.last, 'false');
    expect(b.calls.where((c) => c.startsWith('move')), ['move 110,60']);
  });

  test('выбор окна "процесс|заголовок"', () {
    const w = WindowInfo(1, 'Отчёт — Блокнот', 'Notepad.exe', 1, 0, 0, 1, 1);
    expect(w.matches('notepad|отчёт'), isTrue);
    expect(w.matches('notepad|другое'), isFalse);
    expect(w.matches('chrome|отчёт'), isFalse);
    expect(w.matches('notepad'), isTrue);
  });

  test('имена скриптов с папками очищаются', () {
    expect(ScriptStore.sanitize(r' Игры\Фарм/../a:b.cks '), 'Игры/Фарм/a_b');
    expect(ScriptStore.folderOf('A/B/c'), 'A/B');
    expect(ScriptStore.baseOf('A/B/c'), 'c');
    expect(ScriptStore.folderOf('c'), '');
  });

  test('zip: упаковка и распаковка с русскими именами и папками', () {
    final files = {
      'Примеры/Пример 1.cks': utf8.encode('click(50%, 50%)\n' * 200),
      'a.cks': utf8.encode(''),
    };
    final back = zipDecode(zipEncode(files));
    expect(back.keys.toSet(), files.keys.toSet());
    expect(utf8.decode(back['Примеры/Пример 1.cks']!), 'click(50%, 50%)\n' * 200);
    expect(back['a.cks'], isEmpty);
    expect(() => zipDecode(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('расписание: ежедневно и по интервалу', () {
    final since = DateTime(2026, 1, 1, 8, 0);
    final daily = ScheduleTask(script: 's', mode: 'daily', time: '14:30');
    expect(daily.isDue(DateTime(2026, 1, 1, 14, 29, 59), since), isFalse);
    expect(daily.isDue(DateTime(2026, 1, 1, 14, 30, 5), since), isTrue);
    expect(daily.isDue(DateTime(2026, 1, 1, 14, 45), since), isFalse); // too late
    daily.lastRun = DateTime(2026, 1, 1, 14, 30, 5);
    expect(daily.isDue(DateTime(2026, 1, 1, 14, 31), since), isFalse);
    expect(daily.isDue(DateTime(2026, 1, 2, 14, 30, 1), since), isTrue);

    final every = ScheduleTask(script: 's', mode: 'interval', everyMin: 10);
    expect(every.isDue(DateTime(2026, 1, 1, 8, 9), since), isFalse);
    expect(every.isDue(DateTime(2026, 1, 1, 8, 10), since), isTrue);
    every.lastRun = DateTime(2026, 1, 1, 8, 10);
    expect(every.isDue(DateTime(2026, 1, 1, 8, 15), since), isFalse);
    every.enabled = false;
    expect(every.isDue(DateTime(2026, 1, 1, 9, 0), since), isFalse);
    expect(ScheduleTask.parseTime('25:00'), isNull);
    expect(ScheduleTask.parseTime('7:05'), (h: 7, m: 5));
  });

  test('расписание: один раз в указанный день', () {
    final since = DateTime(2026, 11, 14, 8, 0);
    final once = ScheduleTask(script: 's', mode: 'once', time: '1:46', date: '2026-11-15');
    expect(once.isDue(DateTime(2026, 11, 15, 1, 45), since), isFalse);
    expect(once.isDue(DateTime(2026, 11, 15, 1, 46, 2), since), isTrue);
    expect(once.isDue(DateTime(2026, 11, 15, 2, 0), since), isFalse); // missed by more than 10 min
    expect(once.isDue(DateTime(2026, 11, 16, 1, 46, 2), since), isFalse); // not the next day
    once.lastRun = DateTime(2026, 11, 15, 1, 46, 2);
    expect(once.isDue(DateTime(2026, 11, 15, 1, 47), since), isFalse);
    expect(once.describe(), 'один раз 15.11.2026 в 1:46 — выполнено');
    final back = ScheduleTask.fromJson(once.toJson());
    expect((back.mode, back.date), ('once', '2026-11-15'));

    final now = DateTime(2026, 11, 14);
    expect(ScheduleTask.parseDate('15.11.2026'), '2026-11-15');
    expect(ScheduleTask.parseDate('5.1', now: now), '2026-01-05');
    expect(ScheduleTask.parseDate('15.11.26'), '2026-11-15');
    expect(ScheduleTask.parseDate('2026-11-15'), '2026-11-15');
    expect(ScheduleTask.parseDate('31.02.2026'), isNull);
    expect(ScheduleTask.parseDate('завтра'), isNull);
  });

  test('проверка имён скриптов и папок', () {
    expect(ScriptStore.validateName('Фарм 2 - тест_(v1.5)'), isNull);
    expect(ScriptStore.validateName('Игры/Фарм'), isNull);
    expect(ScriptStore.validateName(r'+*?\'), contains('Нельзя использовать'));
    expect(ScriptStore.validateName('a:b'), contains(':'));
    expect(ScriptStore.validateName('   '), 'Введите имя');
    expect(ScriptStore.validateName('con'), contains('служебное'));
    expect(ScriptStore.validateName('имя.'), contains('точк'));
    expect(ScriptStore.validateName('a/b', allowPath: false), isNotNull);
    expect(ScriptStore.sanitize('+*?'), '___');
  });

  test('запись системных сочетаний при активном окне программы', () async {
    Future<void> ms(int n) => Future<void>.delayed(Duration(milliseconds: n));
    Future<void> tap(StubBackend b, List<int> vks) async {
      for (final vk in vks) {
        b.downVks.add(vk);
        await ms(30);
      }
      for (final vk in vks.reversed) {
        b.downVks.remove(vk);
        await ms(30);
      }
    }

    final b = StubBackend();
    // Our own window is active all the time.
    final rec = Recorder(b, () => true, {});
    rec.start();
    await ms(30);
    await tap(b, [0x5B, 0x10, 0x53]); // Win+Shift+S
    await tap(b, [0x41]); // plain typing into our own editor: ignored
    await tap(b, [0x12, 0x09]); // Alt+Tab
    final lines = rec
        .stop(const RecordOptions())
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('wait'))
        .toList();
    expect(lines, ['key("win+shift+s")', 'key("alt+tab")']);

    rec.start();
    await ms(30);
    await tap(b, [0x5B, 0x10, 0x53]);
    expect(rec.stop(const RecordOptions(systemKeys: false)).trim(), isEmpty);
  });

  test('пошаговый режим останавливается перед каждой строкой', () async {
    var pauses = 0;
    final r = await run('log(1)\nlog(2)\nrepeat (2) { log(3) }', cfg: {'step': true},
        setup: (rt) {
      Timer.periodic(const Duration(milliseconds: 20), (t) {
        if (rt.paused) {
          pauses++;
          rt.paused = false; // "Step" button
        }
        if (pauses > 20) t.cancel();
      });
    });
    expect(r.status, 'ok');
    expect(r.logs, ['1', '2', '3', '3']);
    // line 1, line 2, the repeat line itself, then each of its two passes
    expect(pauses, 5);
    expect(r.events.where((e) => e['t'] == 'paused').length, 5);
  });

  test('точка останова: пауза и значения переменных', () async {
    final r = await run(
        'gold = 5\nfunction add(n) {\n  var t = gold + n\n  return t\n}\n'
        'x = add(2)\nlog(x)\nnames = ["a", "b"]',
        cfg: {'breaks': [4, 7]}, setup: (rt) {
      Timer.periodic(const Duration(milliseconds: 20), (t) {
        if (rt.paused) rt.paused = false; // "Continue"
        if (rt.stopRequested) t.cancel();
      });
    });
    expect(r.status, 'ok');
    expect(r.logs, ['7']);
    final pauses = r.events.where((e) => e['t'] == 'paused').toList();
    expect(pauses.map((e) => e['l']), [4, 7]);
    expect(pauses.every((e) => e['why'] == 'break'), isTrue);
    List<String> rows(Map e) =>
        [for (final m in e['rows'] as List) '${m['s']}|${m['n']}=${m['v']}'];
    final vars = r.events.where((e) => e['t'] == 'vars').toList();
    // At line 4: the function's own variables first, then the script's.
    expect(rows(vars.first), ['add|n=2', 'add|t=7', '|gold=5']);
    expect(rows(vars.last), ['|gold=5', '|x=7', '|names=["a", "b"]']);
  });

  test('значения переменных во время работы и короткий показ', () async {
    final r = await run('i = 0\nrepeat (8) { i++\n wait(100) }', cfg: {'watch': true});
    expect(r.status, 'ok');
    expect(r.events.where((e) => e['t'] == 'vars').length, greaterThan(2));
    expect(ScriptRuntime.preview('abc'), '"abc"');
    expect(ScriptRuntime.preview(List.generate(40, (i) => i)), contains('… всего 40'));
    expect(ScriptRuntime.preview('x' * 500).length, 201);
  });

  test('точки останова сдвигаются вместе со строками', () {
    // Two lines inserted on line 3 (cursor is now on line 5).
    expect(AppController.shiftLines({2, 3, 4, 9}, 2, 5), {2, 3, 6, 11});
    // Lines 4-5 removed (joined into line 3).
    expect(AppController.shiftLines({2, 4, 5, 6, 9}, -2, 3), {2, 4, 7});
  });

  test('подсветка места клика сообщает точку', () async {
    final r = await run('click(100, 200)\nkey("a")', cfg: {'showClicks': true});
    expect(r.status, 'ok');
    final marks = r.events.where((e) => e['t'] == 'mark').toList();
    expect(marks.length, 1);
    expect(marks.first['x'], 100);
    expect(marks.first['y'], 200);
  });

  test('привязка окна в тексте скрипта и выбор окна', () {
    expect(bindingAt('click(1, 1)'), isNull);
    expect(bindingAt('use_window("Game")\nclick(1, 1)'), 'Game');
    expect(bindingAt("use_window('A')\nuse_window(\"B|c\")\n"), 'B|c');
    expect(bindingAt('use_window("Game")\nuse_screen()\n'), isNull);
    expect(bindingAt('use_window("Game")\nuse_window(null)\n'), isNull);
    expect(bindingAt('with_window("A") {\n    click(1, 1)\n'), 'A');
    expect(bindingAt('use_window("B")\nwith_window("A") {\n    if (x) { }\n}\n'), 'B');
    expect(bindingAt('with_window("A", focus: false) {\n    use_window("C")\n'), 'C');
    expect(bindingAt('with_window("A") {\n    use_window("C")\n}\n'), isNull);

    const a = WindowInfo(1, '*Отчёт — Блокнот', 'Notepad.exe', 1, 0, 0, 1, 1);
    const b = WindowInfo(2, 'Другое — Блокнот', 'Notepad.exe', 1, 0, 0, 1, 1);
    const c = WindowInfo(3, 'Game', 'game.exe', 2, 0, 0, 1, 1);
    expect(windowSelector(c, [a, b, c]), 'game.exe');
    expect(windowSelector(a, [a, b, c]), 'Notepad.exe|Отчёт — Блокнот');
    expect(windowSelector(a, [a, c]), 'Notepad.exe');
  });
  test('загрузка процессора, память и system_power', () async {
    expect(await out('''
log(cpu_usage(interval: 100), cpu_usage("game", interval: 100), cpu_usage("nope"))
log(ram_usage(), ram_usage("game.exe"), ram_usage("nope"))
let m = ram_info()
log(m.total, m.free, m.used)
system_power("lock")
'''), ['25 10 null', '75 300 null', '16384 4096 12288']);

    final denied = await run('system_power("shutdown")');
    expect('${denied.result['error']}', contains('Настройки'));
    expect(denied.backend.calls, isNot(contains('power shutdown')));

    final allowed = await run('system_power("sleep")', cfg: {'allowPower': true});
    expect(allowed.result['error'], isNull);
    expect(allowed.backend.calls, contains('power sleep'));

    final dry = await run('system_power("restart")',
        cfg: {'allowPower': true, 'dryRun': true});
    expect(dry.backend.calls, isNot(contains('power restart')));

    final bad = await run('system_power("взорвать")');
    expect('${bad.result['error']}', contains('неизвестное действие'));
  });
  test('точное распознавание по умолчанию, выбор пользователя сохраняется', () {
    expect(Settings().ocrEngine, 'paddle');
    // saved before PaddleOCR became the default: switched once
    expect(Settings.fromJson({'ocrEngine': 'windows'}).ocrEngine, 'paddle');
    final mine = Settings.fromJson({'ocrEngine': 'windows', 'ocrChosen': true});
    expect(mine.ocrEngine, 'windows');
    expect(Settings.fromJson(mine.toJson()).ocrEngine, 'windows');
  });
}
