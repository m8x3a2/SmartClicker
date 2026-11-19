// Comparing an area in place: same / region_diff / snapshot / changed, and
// where a picture was cut from (kept inside the PNG).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/core/vision/bitmap.dart';
import 'package:smart_clicker/core/vision/frame_diff.dart';
import 'package:smart_clicker/core/vision/picture_origin.dart';
import 'package:smart_clicker/core/vision/png.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

/// The screen is one colour; it turns into [later] after [switchAfter]
/// captures (the area "changed").
class _Screen extends StubBackend {
  int captures = 0;
  final int first, later, switchAfter;
  final List<String> areas = [];
  _Screen(this.first, this.later, {this.switchAfter = 1 << 30});

  @override
  Uint8List capture(int x, int y, int w, int h) {
    areas.add('$x,$y,$w,$h');
    pixelColor = captures++ < switchAfter ? first : later;
    return super.capture(x, y, w, h);
  }
}

Bitmap _plain(int w, int h, int rgb) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = rgb & 0xFF;
    px[i * 4 + 1] = (rgb >> 8) & 0xFF;
    px[i * 4 + 2] = (rgb >> 16) & 0xFF;
    px[i * 4 + 3] = 255;
  }
  return Bitmap(w, h, px);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sc_cmp_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(List<String>, Map<String, Object?>)> run(String source, StubBackend b) async {
    final logs = <String>[];
    final rt = ScriptRuntime(b, {'main': 't', 'source': source, 'filesDir': tmp.path}, (e) {
      if (e['t'] == 'log' && e['lv'] == 'info') logs.add('${e['m']}');
    }, random: Random(1));
    final r = await rt.runMain();
    return (logs, r);
  }

  void picture(String name, Bitmap b, {Map<String, String> text = const {}}) =>
      File('${tmp.path}${Platform.pathSeparator}$name.png').writeAsBytesSync(pngEncode(b, text: text));

  test('PNG хранит место, откуда вырезана картинка', () {
    final png = pngEncode(_plain(3, 2, 0x112233), text: originText(820, 400, 3, 2));
    expect(pictureOrigin(png), (x: 820, y: 400, w: 3, h: 2));
    expect(pngDecode(png).w, 3); // the decoder skips the text
    expect(pictureOrigin(pngEncode(_plain(3, 2, 0))), isNull);
    expect(pngText(Uint8List(4)), isEmpty);
  });

  test('pictureDiff: доля точек, отличающихся больше допуска', () {
    final a = _plain(10, 10, 0x808080).bgra;
    final b = Uint8List.fromList(a);
    for (var i = 0; i < 25; i++) {
      b[i * 4] = 0x80 + 30; // a quarter of the pixels: blue +30
    }
    expect(pictureDiff(a, b, 10, 10, tolerance: 20), 0.25);
    expect(pictureDiff(a, b, 10, 10, tolerance: 40), 0);
  });

  test('same / region_diff: место экрана и картинка', () async {
    picture('кнопка', _plain(4, 3, 0x336699));
    final (logs, r) = await run(
        'log(same("кнопка", 10, 20))\nlog(region_diff("кнопка", 10, 20))\nlog(same("кнопка", 10, 20, 4, 3))',
        _Screen(0x336699, 0));
    expect(r['error'], isNull, reason: '$r');
    expect(logs, ['true', '0', 'true']);
    final (logs2, _) = await run('log(same("кнопка", 10, 20))\nlog(region_diff("кнопка", 10, 20))', _Screen(0xFFFFFF, 0));
    expect(logs2, ['false', '100']);
  });

  test('same без места — там, откуда вырезали; без места и без подписи — понятная ошибка', () async {
    picture('бар', _plain(5, 2, 0x10A010), text: originText(300, 900, 5, 2));
    final b = _Screen(0x10A010, 0);
    final (logs, _) = await run('log(same("бар"))', b);
    expect(logs, ['true']);
    expect(b.areas, ['300,900,5,2']);
    picture('чужая', _plain(5, 2, 0));
    final (_, r) = await run('same("чужая")', _Screen(0, 0));
    expect('${r['error']}', contains('same("чужая", x, y)'));
    final (_, r2) = await run('same("бар", 1, 2, 50, 50)', _Screen(0, 0));
    expect('${r2['error']}', contains('5 × 2'));
  });

  test('snapshot / changed: область изменилась', () async {
    final (logs, r) = await run(
        'let s = snapshot(0, 0, 8, 8)\nlog(changed(s))\nlog(same(s))\nlog(changed(s))\nlog(region_diff(s))',
        _Screen(0x202020, 0xE0E0E0, switchAfter: 3));
    expect(r['error'], isNull, reason: '$r');
    // captures 1-3: the snapshot, changed(), same() — as before; then the screen changes
    expect(logs, ['false', 'true', 'true', '100']);
  });

  test('screenshot запоминает место в картинке', () async {
    final (_, r) = await run('screenshot("кусок", 100, 50, 20, 10)', _Screen(0x123456, 0));
    expect(r['error'], isNull, reason: '$r');
    final png = File('${tmp.path}${Platform.pathSeparator}кусок.png').readAsBytesSync();
    expect(pictureOrigin(png), (x: 100, y: 50, w: 20, h: 10));
  });
}
