// The mark of a click: dot, ring, crosshair — where they are coloured.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/storage.dart';
import 'package:smart_clicker/platform/click_marker.dart';

void main() {
  /// Alpha and colour (RGB, un-premultiplied roughly) at (x, y).
  (int, int) at(String shape, int size, int x, int y) {
    final side = clickMarkSide(shape, size);
    final px = drawClickMark(shape, 0xE5484D, size);
    final i = (y * side + x) * 4;
    return (px[i + 3], (px[i + 2] << 16) | (px[i + 1] << 8) | px[i]);
  }

  test('точка: закрашен центр, белый край, углы прозрачны', () {
    final side = clickMarkSide('dot', 14);
    final c = side ~/ 2;
    expect(at('dot', 14, c, c), (255, 0xE5484D));
    final edge = at('dot', 14, c + 8, c).$2; // the edge: white (premultiplied by its alpha)
    expect([edge >> 16, (edge >> 8) & 0xFF, edge & 0xFF].every((v) => v == edge & 0xFF && v > 0xE0), isTrue);
    expect(at('dot', 14, 0, 0).$1, 0);
  });

  test('кольцо: центр пустой, цвет на радиусе', () {
    final side = clickMarkSide('ring', 14);
    final c = side ~/ 2;
    expect(at('ring', 14, c, c).$1, 0); // the point itself stays visible
    expect(at('ring', 14, c + 14, c), (255, 0xE5484D));
  });

  test('перекрестие: пустой центр, цвет на лучах, между лучами пусто', () {
    final side = clickMarkSide('cross', 14);
    final c = side ~/ 2;
    expect(at('cross', 14, c, c).$1, 0);
    expect(at('cross', 14, c + 8, c), (255, 0xE5484D));
    expect(at('cross', 14, c, c - 8), (255, 0xE5484D));
    expect(at('cross', 14, c + 8, c + 8).$1, 0);
  });

  test('настройки отметки: по умолчанию точка, неизвестный вид — точка', () {
    final s = Settings();
    expect(s.clickMarkShape, 'dot');
    expect(Settings.fromJson({...s.toJson(), 'clickMarkShape': 'star'}).clickMarkShape, 'dot');
    expect(Settings.fromJson({...s.toJson(), 'clickMarkShape': 'cross', 'clickMarkSize': 500}).clickMarkSize, 80);
  });
}
