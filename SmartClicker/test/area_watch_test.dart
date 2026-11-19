// Colour of an area (avg / median / main), hue and brightness, and watch():
// parsing `when:`, one check, the reaction in a running script.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/vision/area_color.dart';
import 'package:smart_clicker/core/vision/area_watch.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

/// BGRA of [n] pixels of [rgb].
Uint8List _px(int n, int rgb) {
  final out = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    out[i * 4] = rgb & 0xFF;
    out[i * 4 + 1] = (rgb >> 8) & 0xFF;
    out[i * 4 + 2] = (rgb >> 16) & 0xFF;
    out[i * 4 + 3] = 255;
  }
  return out;
}

/// The screen is [colors][k] on the k-th capture (the last one after that).
class _Screen extends StubBackend {
  final List<int> colors;
  int captures = 0;
  _Screen(this.colors);

  @override
  Uint8List capture(int x, int y, int w, int h) {
    pixelColor = colors[min(captures++, colors.length - 1)];
    return super.capture(x, y, w, h);
  }
}

void main() {
  test('цвет области: среднее, медиана, основной', () {
    // 8 pixels of dark red and 2 of white (a popup over a part of the area)
    final px = Uint8List.fromList([..._px(8, 0x800000), ..._px(2, 0xFFFFFF)]);
    expect(areaColor(px), 0x993333); // the average is pulled to white
    expect(areaColor(px, mode: 'median'), 0x800000);
    expect(areaColor(px, mode: 'main'), 0x800000);
    expect(areaColor(Uint8List(0)), 0);
  });

  test('оттенок, яркость, насыщенность, разница по оттенку', () {
    expect(hueOf(0xFF0000), 0);
    expect(hueOf(0x00FF00), 120);
    expect(hueOf(0x0000FF), 240);
    expect(hueOf(0x808080), 0);
    expect(brightnessOf(0xFFFFFF), 255);
    expect(brightnessOf(0x000000), 0);
    expect(saturationOf(0x808080), 0);
    expect(saturationOf(0xFF0000), 100);
    // the same red in shadow: far by channels, close by hue
    expect(colorDistance(0xC0392B, 0x601C15), greaterThan(90));
    expect(colorDistance(0xC0392B, 0x601C15, by: 'hue'), lessThan(3));
    expect(colorDistance(0xFF0000, 0xFF00F0, by: 'hue'), 56); // 0° vs 304°
    expect(colorDistance(0x000000, 0xFFFFFF, by: 'bright'), 255);
  });

  test('when: понятные слова', () {
    expect(parseWatchRule('')!.kind, 'changed');
    expect(parseWatchRule('Изменилась')!.kind, 'changed');
    expect(parseWatchRule('стала #ff0000')!.color, 0xFF0000);
    expect(parseWatchRule('#00FF00')!.kind, 'color');
    expect(parseWatchRule('светлее 120')!.level, 120);
    expect(parseWatchRule('darker 80')!.kind, 'darker');
    expect(parseWatchRule('не меняется 10s')!.ms, 10000);
    expect(parseWatchRule('не меняется 2 мин')!.ms, 120000);
    expect(parseWatchRule('still 500ms')!.ms, 500);
    expect(parseWatchRule('что-то'), isNull);
    expect(parseWatchRule('светлее'), isNull);
  });

  test('watchStep: изменилась — один раз на изменение', () {
    const rule = WatchRule('changed');
    final st = WatchState();
    bool step(int rgb) => watchStep(rule, st, _px(16, rgb), 4, 4, 0);
    expect(step(0x101010), isFalse); // remembered
    expect(step(0x101010), isFalse);
    expect(step(0xF0F0F0), isTrue); // changed
    expect(step(0xF0F0F0), isFalse); // the new look is the reference now
    expect(step(0x101010), isTrue);
  });

  test('watchStep: цвет и яркость — при переходе в «да»', () {
    final st = WatchState();
    bool color(int rgb) => watchStep(const WatchRule('color', color: 0xFF0000), st, _px(4, rgb), 2, 2, 0);
    expect(color(0x00FF00), isFalse);
    expect(color(0xF00505), isTrue); // within tolerance 20
    expect(color(0xF00505), isFalse); // still red: not again
    expect(color(0x00FF00), isFalse);
    expect(color(0xFF0000), isTrue);
    final dark = WatchState();
    expect(watchStep(const WatchRule('darker', level: 60), dark, _px(4, 0x202020), 2, 2, 0), isTrue);
  });

  test('watchStep: не меняется N секунд', () {
    const rule = WatchRule('still', ms: 1000);
    final st = WatchState();
    expect(watchStep(rule, st, _px(4, 0x111111), 2, 2, 0), isFalse);
    expect(watchStep(rule, st, _px(4, 0x999999), 2, 2, 500), isFalse); // moved: count again
    expect(watchStep(rule, st, _px(4, 0x999999), 2, 2, 1200), isFalse); // 700 ms still
    expect(watchStep(rule, st, _px(4, 0x999999), 2, 2, 1600), isTrue); // 1100 ms still
    expect(watchStep(rule, st, _px(4, 0x999999), 2, 2, 3000), isFalse); // once
  });

  test('watch в скрипте: срабатывает на изменение, получает цвет', () async {
    final logs = <String>[];
    final rt = ScriptRuntime(
        _Screen([0x101010, 0x101010, 0x101010, 0xE0E0E0]),
        {
          'main': 't',
          'source': 'watch(0, 0, 4, 4, (a) => { log("сработало", a.color) }, every: 100)\nwait(900)',
        },
        (e) {
          if (e['t'] == 'log' && e['lv'] == 'info') logs.add('${e['m']}');
        },
        random: Random(1));
    final r = await rt.runMain();
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['⚡ Реакция (область изменилась)', 'сработало #E0E0E0']);
  });

  test('watch: понятные ошибки', () async {
    Future<String> err(String src) async {
      final rt = ScriptRuntime(StubBackend(), {'main': 't', 'source': src}, (_) {}, random: Random(1));
      return '${(await rt.runMain())['error']}';
    }

    expect(await err('watch(0, 0, 4, 4)'), contains('нужна функция'));
    expect(await err('watch(0, 0, () => {})'), contains('четырьмя числами'));
    expect(await err('watch(0, 0, 4, 4, () => {}, when: "иногда")'), contains('светлее 120'));
  });
}
