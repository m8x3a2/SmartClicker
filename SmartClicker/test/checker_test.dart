import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/core/lang/checker.dart';

void main() {
  final scripts = {'Модули/Общее': 'function farm(n) { click(n, n) }\nlimit = 5'};
  List<Issue> check(String src, {Set<String> images = const {'старт'}}) =>
      checkScript(
          src,
          CheckContext(
            builtins: AppController.builtinNames,
            scriptSource: (n) => scripts[n],
            imageExists: (n) => images.contains(n),
          ));
  List<String> errors(String src) =>
      check(src).where((i) => i.error).map((i) => '${i.line}: ${i.message}').toList();

  test('with_window без блока — ошибка, с блоком — нет', () {
    expect(errors('with_window("game")\nclick(1, 1)').single,
        startsWith('1: with_window пишется с блоком'));
    expect(errors('with_window("game") {\n    click(1, 1)\n}'), isEmpty);
  });

  test('опечатка в команде и подсказка', () {
    final e = errors('wait(1)\nclik(10, 10)\nKey("a")');
    expect(e.length, 2);
    expect(e[0], startsWith("2: неизвестная функция 'clik' — может быть, click?"));
    expect(e[1], contains('может быть, key?'));
  });

  test('переменные: заданные где угодно — известны, незаданная — ошибка', () {
    expect(errors('''
function f(a, b) { total = a + b; return total }
for (i in 1..3) { log(i) }
try { x = 1 } catch (err) { log(err) }
var y = 2
count++
g = (v) => v * 2
log(f(1, 2), y, count, g(3), total, x, now())
clickImage("старт")
'''), isEmpty);
    final e = errors('log(gold)\ngol = 5');
    expect(e.single, startsWith("1: неизвестное имя 'gold'"));
    expect(e.single, contains('может быть, gol?'));
  });

  test('функции и переменные из run_script известны', () {
    expect(errors('run_script("Модули/Общее")\nfarm(limit)'), isEmpty);
    expect(errors('run_script("Нет такого")'), ['1: скрипта "Нет такого" нет']);
  });

  test('картинки: нет файла — ошибка, сделанная screenshot — нет', () {
    expect(errors('click_image("старт")'), isEmpty);
    expect(errors('click_image("финиш")').single, contains('картинки "финиш" нет'));
    expect(errors('screenshot("финиш", 0, 0, 10, 10)\nwait_image("финиш")'), isEmpty);
    expect(errors('n = "x"\nfind_image(n)'), isEmpty); // not a literal: unknown
  });

  test('синтаксическая ошибка', () {
    final i = check('if (x {\n}');
    expect(i.single.error, isTrue);
    expect(i.single.line, 1);
  });

  test('замечания: цикл без паузы и сравнение распознанного текста', () {
    final w = check('repeat { click(1, 1) }\nwhile (true) { click(2, 2) }');
    expect(w.map((i) => i.line), [1, 2]);
    expect(w.every((i) => !i.error && i.message.contains('без паузы')), isTrue);
    expect(check('repeat { click(1, 1); wait(1) }'), isEmpty);
    expect(check('while (true) { if (pixel_is(1, 1, "#000")) { break } }'), isEmpty);
    expect(check('repeat { click_image("старт", timeout: 5s) }'), isEmpty);
    final t = check('if (read_text(0, 0, 10, 10) == "Готово") { }').single;
    expect(t.error, isFalse);
    expect(t.message, contains('text_in'));
  });

  test('примеры и скрипты-проверки проходят проверку без ошибок и замечаний', () {
    for (final e in {...exampleScripts, ...checkScripts}.entries) {
      final found = checkScript(
          e.value,
          CheckContext(
            builtins: AppController.builtinNames,
            scriptSource: (n) => exampleScripts[n.split('/').last],
            imageExists: (_) => true,
          ));
      expect(found, isEmpty, reason: '${e.key}: $found');
    }
  });

  test('настройки перезапуска и проверки сохраняются', () {
    expect(Settings().restartOnError, 0);
    expect(Settings().checkBeforeRun, isTrue);
    final s = Settings.fromJson((Settings()
          ..restartOnError = 3
          ..restartDelaySec = 30
          ..checkBeforeRun = false)
        .toJson());
    expect([s.restartOnError, s.restartDelaySec, s.checkBeforeRun], [3, 30, false]);
  });

  test('у каждого скрипта-проверки есть ожидаемый итог прогона', () {
    expect(checkExpectations.keys.toSet(), checkScripts.keys.toSet());
    final r = BatchResult('Проверки/07 Перезапуск после ошибки', 'error', 2100,
        error: 'нарочная', line: 12, expected: 'error');
    expect(r.fine, isTrue);
    expect(BatchResult('x', 'limit', 20000).fine, isTrue);
    expect(BatchResult('x', 'error', 1).fine, isFalse);
    expect(BatchResult('Проверки/04', 'error', 1, expected: 'ok').describe(), contains('ожидалось: завершён'));
  });
}
