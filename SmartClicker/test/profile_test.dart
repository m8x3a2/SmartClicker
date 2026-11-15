// Profiler: the time of a run per line of the main script and per function.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/state/app_controller.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

void main() {
  test('самая долгая строка и функция видны в профиле', () async {
    const src = 'log("начало")\nrepeat (3) {\n    wait(120)\n}\nclick(1, 2)\n';
    final rt = ScriptRuntime(StubBackend(), {'main': 't', 'source': src, 'dryRun': true}, (_) {},
        random: Random(1));
    final r = await rt.runMain();
    expect(r['error'], isNull, reason: '$r');
    final p = RunProfile.of('t', src, (r['ms'] as num).toInt(), r['profile'] as Map);
    final (line, us, hits) = p.lines.first;
    expect(line, 3, reason: 'больше всего времени — в wait');
    expect(hits, 3);
    expect(us, greaterThan(300000));
    expect(p.lineText(3), 'wait(120)');
    final wait = p.calls.firstWhere((c) => c.$1 == 'wait');
    expect(wait.$2, 3);
    expect(p.calls.first.$1, 'wait');
    expect(p.calls.any((c) => c.$1 == 'click'), isTrue);
  });
}
