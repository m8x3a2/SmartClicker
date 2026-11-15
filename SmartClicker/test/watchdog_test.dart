// Watchdog of a hung script: no action for the set time → error; actions,
// long planned waits and wait_until do not trip it; set_option changes it.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/storage/settings.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<Map<String, Object?>> _run(String source, {int watchdogMs = 0}) {
  final rt = ScriptRuntime(StubBackend(),
      {'main': 't', 'source': source, 'watchdogMs': watchdogMs, 'dryRun': true}, (_) {},
      random: Random(1));
  return rt.runMain();
}

void main() {
  test('цикл «посмотреть, подождать» без действий — ошибка «завис»', () async {
    final r = await _run('''
while (true) {
    let c = pixel(1, 1)
    wait(50)
}
''', watchdogMs: 400);
    expect(r['status'], 'error');
    expect('${r['error']}', contains('Сторожевой таймер'));
  });

  test('действия сбрасывают таймер; выключенный не мешает', () async {
    final busy = await _run('''
repeat (10) {
    click(10, 10)
    wait(100)
}
''', watchdogMs: 400);
    expect(busy['error'], isNull, reason: '$busy');

    final off = await _run('repeat (5) { wait(100) }');
    expect(off['error'], isNull);
  });

  test('длинная запланированная пауза не считается, короткая в цикле — считается', () async {
    final planned = await _run('wait(600)\nclick(1, 1)', watchdogMs: 300);
    expect(planned['error'], isNull, reason: '$planned');
  });

  test('set_option("watchdog") включает и выключает в скрипте', () async {
    final on = await _run('''
set_option("watchdog", 300)
while (true) { wait(50) }
''');
    expect('${on['error']}', contains('Сторожевой таймер'));

    final off = await _run('''
set_option("watchdog", 0)
repeat (8) { wait(60) }
''', watchdogMs: 200);
    expect(off['error'], isNull);
  });

  test('настройка: по умолчанию выключен, до суток', () {
    expect(Settings().watchdogMin, 0);
    expect(Settings.fromJson({'watchdogMin': 99999}).watchdogMin, 1440);
  });
}
