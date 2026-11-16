// wait_change / wait_still: the share of changed pixels, waiting for a
// change of an area and for it to calm down.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/vision/frame_diff.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Future<(List<String>, Map<String, Object?>)> _run(String source, StubBackend b,
    {Future<void> Function()? meanwhile}) async {
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(b, {'main': 't', 'source': source}, events.add, random: Random(1));
  final done = rt.runMain();
  if (meanwhile != null) await meanwhile();
  final r = await done;
  return ([for (final e in events) if (e['t'] == 'log' && e['lv'] == 'info') '${e['m']}'], r);
}

void main() {
  test('доля изменившихся точек, допуск', () {
    Uint8List px(int n, int v) => Uint8List.fromList([for (var i = 0; i < n; i++) ...[v, v, v, 255]]);
    final a = px(100, 10);
    final b = Uint8List.fromList(a)..setRange(0, 40, px(10, 200));
    expect(changedShare(a, b, 10, 10), closeTo(0.1, 1e-9));
    expect(changedShare(a, px(100, 15), 10, 10), 0, reason: 'мелкое отличие — в пределах допуска');
    expect(changedShare(a, px(100, 15), 10, 10, tolerance: 5), 1);
  });

  test('wait_change: дождались изменения; без изменений — время вышло', () async {
    final b = StubBackend()..pixelColor = 0x101010;
    final (logs, r) = await _run('log(wait_change(0, 0, 20, 20, timeout: 3s, interval: 50))', b,
        meanwhile: () async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      b.pixelColor = 0xF0F0F0;
    });
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['true']);

    final (logs2, _) = await _run('log(wait_change(0, 0, 20, 20, timeout: 300, interval: 50))', StubBackend());
    expect(logs2, ['false']);
  });

  test('wait_still: дождались покоя после мелькания; всё время меняется — время вышло', () async {
    final b = StubBackend();
    var stop = false;
    Future<void> flicker(Duration d) async {
      final sw = Stopwatch()..start();
      while (!stop && sw.elapsed < d) {
        b.pixelColor = b.pixelColor == 0 ? 0xFFFFFF : 0;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    final sw = Stopwatch()..start();
    final (logs, r) = await _run('log(wait_still(0, 0, 20, 20, still: 400, interval: 50, timeout: 5s))', b,
        meanwhile: () => flicker(const Duration(milliseconds: 600)));
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['true']);
    expect(sw.elapsedMilliseconds, greaterThan(900), reason: 'покой отсчитывается после мелькания');

    final b2 = StubBackend();
    final (logs2, _) = await _run('log(wait_still(0, 0, 20, 20, still: 2s, interval: 50, timeout: 700))', b2,
        meanwhile: () async {
      final sw2 = Stopwatch()..start();
      while (sw2.elapsedMilliseconds < 900) {
        b2.pixelColor = b2.pixelColor == 0 ? 0xFFFFFF : 0;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    expect(logs2, ['false']);
    stop = true;
  });
}
