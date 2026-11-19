// The mark of a click shown on the screen just before it (setting «Показывать
// место клика», the ghost): a dot, a ring or a crosshair. Pure drawing.

import 'dart:math' as math;
import 'dart:typed_data';

/// Shapes of the click mark, as stored in the settings.
const clickMarkShapes = {'dot': 'Точка', 'ring': 'Кольцо', 'cross': 'Перекрестие'};

/// Side of the square picture for a mark of [size] px (the diameter of the
/// dot, the radius of the ring, the arm of the crosshair).
int clickMarkSide(String shape, int size) {
  final s = size.clamp(4, 80);
  return switch (shape) {
    'ring' => s * 2 + 10,
    'cross' => s * 2 + 6,
    _ => s + 6,
  };
}

/// Premultiplied BGRA picture of a mark of [shape], [rgb] and [size] with
/// a white edge (seen on any background), centred: the centre pixel of a
/// side × side square ([clickMarkSide]).
Uint8List drawClickMark(String shape, int rgb, int size) {
  final s = size.clamp(4, 80);
  final side = clickMarkSide(shape, s);
  final px = Uint8List(side * side * 4);
  final c = (side - 1) / 2;
  final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;

  void put(int x, int y, double alpha, bool edge) {
    final a = (255 * alpha.clamp(0.0, 1.0)).round();
    final i = (y * side + x) * 4;
    if (a <= px[i + 3]) return; // the stronger cover stays
    final (cr, cg, cb) = edge ? (255, 255, 255) : (r, g, b);
    px[i] = cb * a ~/ 255;
    px[i + 1] = cg * a ~/ 255;
    px[i + 2] = cr * a ~/ 255;
    px[i + 3] = a;
  }

  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final dx = x - c, dy = y - c;
      final d = math.sqrt(dx * dx + dy * dy);
      switch (shape) {
        case 'ring':
          // a ring 4 px wide at radius s, a white edge 1.5 px on both sides
          final off = (d - s).abs();
          if (off <= 2.5) {
            put(x, y, 3.0 - off, false);
          } else if (off <= 4.5) {
            put(x, y, 5.0 - off, true);
          }
        case 'cross':
          // two arms 2 px thick with a gap of 3 px around the point itself
          final ax = dx.abs(), ay = dy.abs();
          final arm = math.max(ax, ay), across = math.min(ax, ay);
          if (arm > s + 0.5 || arm < 3) break;
          if (across <= 1.0) {
            put(x, y, 1, false);
          } else if (across <= 2.5) {
            put(x, y, 3.0 - across, true);
          }
        default:
          // a filled dot with a white edge
          final rad = s / 2;
          if (d <= rad) {
            put(x, y, rad + 0.5 - d, false);
          } else if (d <= rad + 2) {
            put(x, y, rad + 2.5 - d, true);
          }
      }
    }
  }
  return px;
}
