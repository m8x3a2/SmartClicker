// show("Убито", kills): values for the mini panel — sent when they change,
// removed, limited; variables pinned in the «Переменные» tab are sent too.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(List<String>, Map<String, Object?>)> _run(String source, {List<String> pin = const []}) async {
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(StubBackend(), {'main': 't', 'source': source, 'pin': pin}, events.add,
      random: Random(1));
  final r = await rt.runMain();
  return ([for (final e in events) if (e['t'] == 'show') '${e['k']}=${e['v']}'], r);
}

void main() {
  test('show: значение уходит при изменении, show("…") без значения убирает', () async {
    final (shown, r) = await _run('''
let kills = 0
repeat (3) {
  kills++
  show("Убито", kills)
  show("Золото", 100)
}
show("Золото")
show("Нет такого")
''');
    expect(r['error'], isNull, reason: '$r');
    expect(shown, ['Убито=1', 'Золото=100', 'Убито=2', 'Убито=3', 'Золото=null']);
  });

  test('show: не больше 4 значений, пустая подпись — ошибка', () async {
    final (_, r) = await _run('for (i in 1..5) { show("v" + i, i) }');
    expect('${r['error']}', contains('помещается 4'));
    final (_, r2) = await _run('show("", 1)');
    expect('${r2['error']}', contains('пустой'));
  });

  test('закреплённые переменные приходят сами и в конце запуска', () async {
    final (shown, r) = await _run('let gold = 5\nwait(700)\ngold = 7\nwait(700)\ngold = 9', pin: ['gold', 'nothing']);
    expect(r['error'], isNull, reason: '$r');
    expect(shown.first, 'gold=5');
    expect(shown.last, 'gold=9', reason: 'последнее значение отправлено в конце');
    expect(shown.where((s) => s.startsWith('nothing')), isEmpty);
  });
}
