// Pause after every input action (action_delay) and the slow run.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(int ms, Map<String, Object?> result, List<Map<String, Object?>> events)> timed(
    String source, Map<String, Object?> cfg) async {
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(StubBackend(), {'main': 't', 'source': source, ...cfg}, events.add,
      random: Random(1));
  final sw = Stopwatch()..start();
  final result = await rt.runMain();
  return (sw.elapsedMilliseconds, result, events);
}

void main() {
  test('пауза после каждого действия: из настроек и set_option', () async {
    const clicks = 'click(10, 10)\nclick(20, 20)\nclick(30, 30)\nlog("ok")';
    final plain = await timed(clicks, {});
    expect(plain.$2['status'], 'ok');
    // Generous bounds: the machine may be busy with other tests.
    expect(plain.$1, lessThan(400));

    final slow = await timed(clicks, {'actionDelay': 200});
    expect(slow.$2['status'], 'ok');
    expect(slow.$1, greaterThanOrEqualTo(3 * 200 - 10));

    // Only after input actions: calculations and logs are not slowed down.
    final calc = await timed('let s = 0\nfor (let i = 0; i < 20; i++) { s += i }\nlog(s)',
        {'actionDelay': 500});
    expect(calc.$1, lessThan(400));

    final opt = await timed('set_option("action_delay", 100)\nkey("a")\nkey("b")\nlog(1)', {});
    expect(opt.$2['status'], 'ok');
    expect(opt.$1, greaterThanOrEqualTo(2 * 100 - 10));

    // The test mode keeps the same timing.
    final dry = await timed(clicks, {'actionDelay': 80, 'dryRun': true});
    expect(dry.$1, greaterThanOrEqualTo(3 * 80 - 10));
  });

  test('замедленный запуск: пауза перед каждой строкой и подсветка', () async {
    final r = await timed('let a = 1\nlet b = 2\nlog(a + b)', {'slowMs': 100});
    expect(r.$2['status'], 'ok');
    expect(r.$1, greaterThanOrEqualTo(3 * 100 - 10));
    final lines = r.$3.where((e) => e['t'] == 'line').map((e) => e['l']).toList();
    expect(lines, containsAllInOrder([1, 2, 3]));

    // A loop on one line still slows down on every pass.
    final loop = await timed('for (let i = 0; i < 3; i++) { log(i) }', {'slowMs': 60});
    expect(loop.$1, greaterThanOrEqualTo(3 * 60 - 10));
  });
}
