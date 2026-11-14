// ask(): questions found before the run, kinds of fields, remembered
// answers, the engine's answers and the checker's warning.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/app/ui/scripts/ask_dialog.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/lang/ask_scan.dart';
import 'package:smart_clicker/core/lang/checker.dart';
import 'package:smart_clicker/core/storage/check_scripts.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(List<String>, List<String>)> run(String source, Map<String, Object?> answers) async {
  final events = <Map<String, Object?>>[];
  final data = '${Directory.systemTemp.createTempSync('ask_test').path}/data.json';
  final rt = ScriptRuntime(
      StubBackend(), {'main': 't', 'source': source, 'answers': answers, 'dataFile': data},
      events.add,
      random: Random(1));
  final result = await rt.runMain();
  expect(result['error'], isNull, reason: '$result');
  List<String> of(String lv) =>
      [for (final e in events) if (e['t'] == 'log' && e['lv'] == lv) '${e['m']}'];
  return (of('info'), of('warn'));
}

void main() {
  test('вопросы находятся по порядку, вид поля — по значению по умолчанию', () {
    final asks = findAsks('''
let times = ask("Сколько раз?", 10)
let mode = ask("Режим", "быстро", options: ["быстро", "медленно"])
let sell = ask("Продавать?", true)
let name = ask("Имя")
let neg = ask("Сдвиг", -5)
let pick = ask("Цвет", ["красный", "синий"])
function f() { return ask("Сколько раз?", 3) }   // the same question again
''');
    expect(asks.map((a) => a.prompt),
        ['Сколько раз?', 'Режим', 'Продавать?', 'Имя', 'Сдвиг', 'Цвет']);
    expect(asks.map((a) => a.kind), [
      AskKind.number, AskKind.choice, AskKind.flag, AskKind.text, AskKind.number, AskKind.choice
    ]);
    expect(asks[0].def, 10);
    expect(asks[1].options, ['быстро', 'медленно']);
    expect(asks[3].def, '');
    expect(asks[4].def, -5);
    expect(asks[5].def, 'красный');
    expect(asks[0].line, 1);
  });

  test('вопросы из скриптов run_script, без зацикливания', () {
    final others = {
      'A': 'let a = ask("Из A", 1)\nrun_script("B")',
      'B': 'let b = ask("Из B", "x")\nrun_script("A")',
    };
    final asks = findAsks('ask("Главный", false)\nrun_script("A")', (n) => others[n]);
    expect(asks.map((a) => a.prompt), ['Главный', 'Из A', 'Из B']);
  });

  test('вычисляемые вопросы и скрипт с ошибкой не дают вопросов', () {
    expect(findAsks(r'let n = 5' '\n' r'ask(`Сколько ${n}?`, 1)' '\nask("Сколько", n)'), isEmpty);
    expect(findAsks('ask("Сколько", 1'), isEmpty);
  });

  test('значение по умолчанию вне списка — первый вариант; старый ответ не подходит — по умолчанию', () {
    final a = askSpec('Режим', 'нет такого', ['a', 'b']);
    expect(a.def, 'a');
    expect(a.pick('b'), 'b');
    expect(a.pick('c'), 'a');
    final n = askSpec('Сколько', 10, null);
    expect(n.pick(200), 200);
    expect(n.pick('200'), 10); // the question used to be a text one
    expect(defaultAnswers([n, a], {'Сколько': 7}), {'Сколько': 7, 'Режим': 'a'});
    expect(describeAnswers({'Сколько': 7, 'Режим': 'a', 'Да?': true}),
        'Сколько = 7 · Режим = "a" · Да? = да');
  });

  test('движок: ответ из окна, иначе значение по умолчанию с предупреждением', () async {
    final (logs, warns) = await run(r'''
let times = ask("Сколько раз?", 10)
let mode = ask("Режим", "быстро", options: ["быстро", "медленно"])
let n = 3
let other = ask(`Вопрос ${n}`, 42)
log(times, mode, other)
''', {'Сколько раз?': 200, 'Режим': 'медленно'});
    expect(logs, ['200 медленно 42']);
    expect(warns.single, contains('Вопрос 3'));
  });

  test('движок: ответ не того вида не подставляется', () async {
    final (logs, _) = await run('log(ask("Сколько", 5), ask("Да?", true))',
        {'Сколько': 'много', 'Да?': false});
    expect(logs, ['5 false']);
  });

  test('проверка: замечание о вычисляемом вопросе', () {
    final issues = checkScript(
        'let n = 2\nlet a = ask("Сколько?", 10)\nlet b = ask("Сколько?", n)',
        CheckContext(
          builtins: AppController.builtinNames,
          scriptSource: (_) => null,
          imageExists: (_) => true,
        ));
    expect(issues.length, 1);
    expect(issues.single.line, 3);
    expect(issues.single.error, isFalse);
  });

  test('числа в окне: пробелы, запятая, минус', () {
    expect(parseAnswerNumber('1 000'), 1000);
    expect(parseAnswerNumber('1,5'), 1.5);
    expect(parseAnswerNumber(' -3 '), -3);
    expect(parseAnswerNumber('2.0'), 2.0);
    expect(parseAnswerNumber('abc'), isNull);
    expect(parseAnswerNumber(''), isNull);
  });

  testWidgets('окно вопросов: поля, проверка числа, ответы', (tester) async {
    final asks = findAsks('''
ask("Сколько раз?", 10)
ask("Режим", "быстро", options: ["быстро", "медленно"])
ask("Продавать?", false)
ask("Имя", "Вася")
''');
    Map<String, Object?>? got;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            got = await showAskDialog(context, 'Фарм', asks,
                defaultAnswers(asks, {'Режим': 'медленно'}));
            closed = true;
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Запуск «Фарм»'), findsOneWidget);
    expect(find.text('медленно'), findsOneWidget); // the remembered answer

    await tester.enterText(find.widgetWithText(TextField, 'Сколько раз?'), 'много');
    await tester.tap(find.text('Запустить'));
    await tester.pumpAndSettle();
    expect(find.text('Нужно число'), findsOneWidget);
    expect(closed, isFalse);

    await tester.enterText(find.widgetWithText(TextField, 'Сколько раз?'), '1 500');
    await tester.tap(find.text('Продавать?'));
    await tester.tap(find.text('Запустить'));
    await tester.pumpAndSettle();
    expect(got, {'Сколько раз?': 1500, 'Режим': 'медленно', 'Продавать?': true, 'Имя': 'Вася'});

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(got, isNull);
  });

  test('скрипты-проверки с вопросами выполняются до конца', () async {
    for (final name in ['08 Вопросы при запуске', '09 Почти всё']) {
      final (logs, _) = await run(checkScripts[name]!, {'Сколько раз?': 1, 'Сколько кругов?': 1});
      expect(logs.last, anyOf(contains('Готово'), contains('Всё прошло')), reason: name);
    }
  });
}
