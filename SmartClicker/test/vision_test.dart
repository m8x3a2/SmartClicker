import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/services/ocr_install.dart';
import 'package:smart_clicker/core/vision/image.dart';
import 'package:smart_clicker/core/vision/paddle_ocr.dart';
import 'package:smart_clicker/core/vision/ocr.dart';
import 'package:smart_clicker/core/engine/runtime.dart';
import 'package:smart_clicker/platform/stub_backend.dart';

Bitmap noise(int w, int h, int seed) {
  final r = Random(seed);
  final b = Uint8List(w * h * 4);
  for (var i = 0; i < b.length; i++) {
    b[i] = i % 4 == 3 ? 255 : r.nextInt(256);
  }
  return Bitmap(w, h, b);
}

Bitmap crop(Bitmap s, int x, int y, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final from = ((y + row) * s.w + x) * 4;
    out.setRange(row * w * 4, (row + 1) * w * 4, s.bgra, from);
  }
  return Bitmap(w, h, out);
}

/// Button-like picture: border, filled body, a few dark "letters".
Bitmap button(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      var c = [200, 120, 40]; // body (BGR)
      if (x < 2 || y < 2 || x >= w - 2 || y >= h - 2) c = [30, 30, 30];
      final lx = (x - 6) % 8;
      if (x >= 6 && x < w - 6 && lx < 4 && y >= h ~/ 3 && y < h * 2 ~/ 3) {
        c = [250, 250, 250];
      }
      b[i] = c[0];
      b[i + 1] = c[1];
      b[i + 2] = c[2];
      b[i + 3] = 255;
    }
  }
  return Bitmap(w, h, b);
}

void paste(Bitmap dst, Bitmap src, int x, int y) {
  for (var row = 0; row < src.h; row++) {
    dst.bgra.setRange(((y + row) * dst.w + x) * 4,
        ((y + row) * dst.w + x + src.w) * 4, src.bgra, row * src.w * 4);
  }
}

Bitmap scene(int w, int h) {
  final b = Bitmap(w, h, Uint8List(w * h * 4));
  for (var i = 0; i < w * h; i++) {
    b.bgra[i * 4] = 230;
    b.bgra[i * 4 + 1] = 235 - (i ~/ w) % 20;
    b.bgra[i * 4 + 2] = 240;
    b.bgra[i * 4 + 3] = 255;
  }
  // distractor: same colours, different layout
  final d = Bitmap(30, 30, Uint8List(30 * 30 * 4));
  for (var i = 0; i < 900; i++) {
    d.bgra.setRange(i * 4, i * 4 + 4, [200, 120, 40, 255]);
  }
  paste(b, d, 10, 10);
  return b;
}

Future<(List<String>, Map<String, Object?>, StubBackend)> run(String source,
    {StubBackend? backend, String? dir}) async {
  final b = backend ?? StubBackend();
  final events = <Map<String, Object?>>[];
  final rt = ScriptRuntime(
      b, {'main': 't', 'source': source, 'filesDir': ?dir}, events.add,
      random: Random(1));
  final result = await rt.runMain();
  final logs = events
      .where((e) => e['t'] == 'log' && e['lv'] == 'info')
      .map((e) => '${e['m']}')
      .toList();
  return (logs, result, b);
}

void main() {
  test('PNG: запись и чтение дают ту же картинку', () {
    final src = noise(17, 9, 1);
    final back = pngDecode(pngEncode(src));
    expect(back.w, 17);
    expect(back.h, 9);
    expect(back.bgra, src.bgra);
    expect(() => pngDecode(Uint8List(40)), throwsFormatException);
  });

  test('поиск картинки: точное место, допуск, прозрачность', () {
    final screen = noise(120, 80, 2);
    final piece = crop(screen, 37, 21, 16, 12);
    expect(findBitmap(screen, piece, tolerance: 0), (x: 37, y: 21));
    // Slightly different colours are still found with a tolerance.
    final faded = Bitmap(16, 12, Uint8List.fromList(piece.bgra));
    for (var i = 0; i < faded.bgra.length; i++) {
      if (i % 4 != 3) faded.bgra[i] = (faded.bgra[i] + 6).clamp(0, 255);
    }
    expect(findBitmap(screen, faded, tolerance: 0), isNull);
    expect(findBitmap(screen, faded, tolerance: 10), (x: 37, y: 21));
    // Transparent pixels of the sample match anything.
    final holed = Bitmap(16, 12, Uint8List.fromList(piece.bgra));
    for (var i = 0; i < 40; i++) {
      holed.bgra[i * 4] = 1;
      holed.bgra[i * 4 + 3] = 0;
    }
    expect(findBitmap(screen, holed, tolerance: 0), (x: 37, y: 21));
    expect(findBitmap(screen, noise(16, 12, 99)), isNull);
    expect(findBitmap(piece, screen), isNull);
  });

  test('увеличение сохраняет цвета и размеры', () {
    final b = Bitmap(2, 1, Uint8List.fromList([0, 0, 0, 0, 200, 100, 50, 0]));
    final up = upscale(b, 3);
    expect([up.w, up.h], [6, 3]);
    expect(up.bgra.sublist(0, 4), [0, 0, 0, 255]);
    expect(up.bgra.sublist(20, 24), [200, 100, 50, 255]);
    expect(identical(upscale(b, 1), b), isTrue);
  });

  test('текст в области: read_text, text_in, wait_text, read_number', () async {
    final b = StubBackend()..screenText = 'Загрузка  ЗАВЕРШЕНА\nЗолото: 1 234,5';
    final (logs, result, _) = await run('''
log(text_in(10, 20, 300, 60, "загрузка завершена"))
log(text_in(10, 20, 300, 60, "ошибка"))
log(wait_text(10, 20, 300, 60, "золото", timeout: 1s))
log(wait_text(10, 20, 300, 60, "нет такого", timeout: 100, interval: 50))
log(read_number(10, 20, 300, 60))
log(len(read_text(50%, 50%, 10%, 10%)))
''', backend: b);
    expect(result['error'], isNull, reason: '$result');
    expect(logs, ['true', 'false', 'true', 'false', '1234.5', '35']);
    expect(b.calls.first, 'ocr 10 20 300 60');
    final (_, bad, _) = await run('read_text(1, 2)');
    expect('${bad['error']}', contains('четырьмя числами'));
  });

  test('поиск картинки в другом масштабе', () {
    final needle = button(48, 24);
    for (final (k, sw, sh) in [
      (1.5, 320, 200), (0.75, 320, 200), (2.0, 320, 200), (1.25, 320, 200),
      // > 300 000 pixels: coarse search at half resolution first
      (1.5, 800, 450), (0.6, 800, 450), (1.9, 800, 450), (1.0, 800, 450),
    ]) {
      final hay = scene(sw, sh);
      final big = resize(needle, (48 * k).round(), (24 * k).round());
      paste(hay, big, 150, 90);
      if (k != 1) {
        expect(findBitmap(hay, needle), isNull, reason: 'k=$k без масштаба');
      }
      final hit = findBitmapScaled(hay, needle);
      expect(hit, isNotNull, reason: 'k=$k');
      expect(hit!.scale, closeTo(k, 0.05), reason: 'k=$k');
      expect((hit.x + hit.w / 2 - (150 + big.w / 2)).abs(), lessThanOrEqualTo(2));
      expect((hit.y + hit.h / 2 - (90 + big.h / 2)).abs(), lessThanOrEqualTo(2));
      final near = findBitmapScaled(hay, needle,
          minScale: k / 1.06, maxScale: k * 1.06, center: k);
      expect(near, isNotNull, reason: 'k=$k около');
    }
    // a big needle: searched in a shrunk copy of the screen first
    final wide = button(120, 60);
    for (final k in [0.7, 1.6]) {
      final hay = scene(900, 500);
      final big = resize(wide, (120 * k).round(), (60 * k).round());
      paste(hay, big, 333, 211);
      final hit = findBitmapScaled(hay, wide);
      expect(hit, isNotNull, reason: 'большая k=$k');
      expect(hit!.scale, closeTo(k, 0.03));
      expect((hit.x - 333).abs() + (hit.y - 211).abs(), lessThanOrEqualTo(2));
    }
    expect(findBitmapScaled(scene(900, 500), wide), isNull);
    expect(findBitmapScaled(scene(320, 200), needle), isNull);
    expect(findBitmapScaled(scene(800, 450), needle), isNull);
    final same = scene(320, 200);
    paste(same, needle, 40, 120);
    final hit = findBitmapScaled(same, needle)!;
    expect((hit.x, hit.y, hit.scale), (40, 120, 1.0));
  });

  test('порядок масштабов: сначала ближайшие к центру', () {
    final s = searchScales(50, 20, 0.5, 2);
    expect(s.first, 1);
    expect((s[1] - 1) * (s[2] - 1), lessThan(0)); // one up, one down
    expect(s.every((k) => k >= 0.5 - 1e-9 && k <= 2 + 1e-9), isTrue);
    expect(searchScales(50, 20, 1.4, 1.6, center: 1.5).first, 1.5);
    expect(searchScales(50, 20, 1.4, 1.6).first, 1.4);
  });

  test('screenshot + find_image + click_image', () async {
    final dir = Directory.systemTemp.createTempSync('sc_vision');
    try {
      final (logs, result, b) = await run('''
screenshot("кнопка", 100, 100, 20, 10)
p = find_image("кнопка", 300, 200, 50, 50)
log(p.x, p.y, p.w, p.h)
log(click_image("кнопка", 300, 200, 50, 50, offset: 0))
log(find_image("кнопка", scale: 0.5..2).scale)
log(find_image("нет"))
''', dir: dir.path);
      expect(File('${dir.path}/кнопка.png').existsSync(), isTrue);
      expect(logs.first, '310 205 20 10');
      expect(logs[1], 'true');
      expect(logs[2], '1');
      expect(b.calls, contains('down left'));
      expect('${result['error']}', contains('не найдена'));
      final (more, _, _) = await run('''
log(find_image("кнопка", 300, 200, 50, 50, scale: "auto").scale)
log(find_image("кнопка", 300, 200, 50, 50, scale: [0.9, 1.1]).w)
log(find_image("кнопка", 300, 200, 50, 50, scale: 1).x)
''', dir: dir.path);
      expect(more, ['1', '20', '310']);
      final (_, bad, _) = await run(
          'find_image("кнопка", scale: "крупнее")', dir: dir.path);
      expect('${bad['error']}', contains('scale'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('SHA-256 совпадает с эталоном', () {
    expect((Sha256()..add('abc'.codeUnits)).hex(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    final h = Sha256();
    for (var i = 0; i < 1000; i++) {
      h.add(List.filled(1000, 0x61));
    }
    expect(h.hex(),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('нестрогое сравнение текста и выбор движка', () {
    expect(looseText('  PaddleOCR   Готово '), looseText('Раddlеосr готово'));
    expect(looseText('Ёлка'), looseText('елка'));
    expect(ocrEngineId('Paddle'), 'paddle');
    expect(ocrEngineId('точное'), 'paddle');
    expect(ocrEngineId(''), 'windows');
    expect(() => ocrEngineId('tesseract'), throwsArgumentError);
  });

  test('CTC: повторы склеиваются, пустой класс пропускается', () {
    // classes: 0 blank, 1 "а", 2 "б", 3 space
    Float32List steps(List<int> best) {
      final p = Float32List(best.length * 4);
      for (var i = 0; i < best.length; i++) {
        p[i * 4 + best[i]] = 0.9;
      }
      return p;
    }

    final r = ctcDecode(steps([1, 1, 0, 1, 3, 2, 2, 0]), 8, 4, ['а', 'б']);
    expect(r.text, 'аа б');
    expect(r.confidence, closeTo(0.9, 1e-6));
    expect(ctcDecode(steps([0, 0]), 2, 4, ['а', 'б']).text, '');
  });

  test('подготовка картинки для модели: порядок каналов и поля', () {
    // one pixel: B=255, G=0, R=127
    final img = Bitmap(1, 1, Uint8List.fromList([255, 0, 127, 255]));
    final p = toPlanes(img, 0, 0, 1, 1, 2, 2, 3);
    expect(p.length, 3 * 3 * 2);
    expect(p[0], closeTo(1, 1e-6));
    expect(p[6], closeTo(-1, 1e-6));
    expect(p[12], closeTo(127 / 127.5 - 1, 1e-6));
    expect(p[2], 0); // padding
  });

  test('без установленного PaddleOCR скрипт получает понятную ошибку', () async {
    final dir = Directory.systemTemp.createTempSync('sc_noocr');
    try {
      final (_, result, _) = await run(
          'read_text(1, 2, 30, 40, engine: "paddle")',
          dir: dir.path);
      expect('${result['error']}', contains('не установлено'));
      final (_, bad, _) = await run('read_text(1, 2, 30, 40, engine: "x")');
      expect('${bad['error']}', contains('неизвестный движок'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
