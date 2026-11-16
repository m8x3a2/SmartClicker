// Reactions: every (by time), on_key (a key of the user), on_image (a picture
// appeared), off, one at a time, and a clear error without a function.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(List<String>, Map<String, Object?>)> _run(String source,
    {StubBackend? backend, String? dir, Future<void> Function(StubBackend)? meanwhile}) async {
  final b = backend ?? StubBackend();
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(b, {'main': 't', 'source': source, 'filesDir': ?dir}, events.add,
      random: Random(1));
  final done = rt.runMain();
  if (meanwhile != null) await meanwhile(b);
  final r = await done;
  return ([for (final e in events) if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}'], r);
}

void main() {
  test('every: по времени, пока основной код ждёт; off останавливает', () async {
    final (logs, r) = await _run('''
let n = 0
let id = every(200, () => { n += 1 })
wait(1100)
log("раз:", n)
off(id)
wait(500)
log("после off:", n)
''');
    expect(r['error'], isNull, reason: '$r');
    final n = int.parse(logs.firstWhere((l) => l.startsWith('раз:')).split(' ').last);
    expect(n, inInclusiveRange(4, 6));
    expect(logs.last, 'после off: $n');
    expect(logs.where((l) => l.startsWith('⚡ Реакция')).length, n);
  });

  test('on_key: нажатие человека — один раз на нажатие', () async {
    final (logs, r) = await _run('''
on_key("f5", () => { log("F5!") })
wait(900)
''', meanwhile: (b) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      b.downVks.add(0x74); // F5 down and held
      await Future<void>.delayed(const Duration(milliseconds: 250));
      b.downVks.remove(0x74);
    });
    expect(r['error'], isNull, reason: '$r');
    expect(logs.where((l) => l == 'F5!').length, 1);
  });

  test('on_image: видна сразу — реакция; пропала и появилась — ещё раз (с её местом)', () async {
    final dir = Directory.systemTemp.createTempSync('sc_react');
    try {
      final b = StubBackend()..pixelColor = 0x3366AA;
      final (logs, r) = await _run('''
screenshot("цель", 0, 0, 10, 10)
on_image("цель", (p) => { log("вижу", p.w) }, interval: 100)
wait(1200)
''', backend: b, dir: dir.path, meanwhile: (b) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        b.pixelColor = 0x000000; // gone
        await Future<void>.delayed(const Duration(milliseconds: 400));
        b.pixelColor = 0x3366AA; // appeared
      });
      expect(r['error'], isNull, reason: '$r');
      expect(logs.where((l) => l == 'вижу 10').length, 2);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('одна реакция за раз: внутри реакции другие не запускаются', () async {
    final (logs, r) = await _run('''
let depth = 0
let most = 0
every(100, () => {
    depth += 1
    if (depth > most) { most = depth }
    wait(300)
    depth -= 1
})
wait(500)   // реакция дольше своего периода — основной код всё равно идёт
log("глубина:", most)
''');
    expect(r['error'], isNull, reason: '$r');
    expect(logs.last, 'глубина: 1');
  });

  test('без функции — понятная ошибка', () async {
    final (_, r) = await _run('on_key("f5")');
    expect('${r['error']}', contains('нужна функция'));
    final (_, r2) = await _run('every(10, () => {})');
    expect('${r2['error']}', contains('не меньше 100'));
  });
}
