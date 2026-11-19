// The magnifier shown while taking a point: the pixels around the cursor,
// enlarged, with a grid and the pixel under the cursor framed.

import 'dart:typed_data';

import 'bitmap.dart';

/// Opaque BGRA picture of [cells]×[cells] pixels of [src] centred at
/// ([cx], [cy]), each [cell] px, with a 1 px border: (cells·cell + 2)².
/// Pixels outside [src] are dark grey. Pure.
Bitmap loupeImage(Bitmap src, int cx, int cy, {int cells = 15, int cell = 10}) {
  final size = cells * cell + 2;
  final out = Uint8List(size * size * 4);
  final half = cells ~/ 2;
  final grid = cell >= 6;

  void put(int x, int y, int b, int g, int r) {
    final i = (y * size + x) * 4;
    out[i] = b;
    out[i + 1] = g;
    out[i + 2] = r;
    out[i + 3] = 255;
  }

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (x == 0 || y == 0 || x == size - 1 || y == size - 1) {
        put(x, y, 0x85, 0x74, 0x6B); // border #6B7485
        continue;
      }
      final lx = x - 1, ly = y - 1;
      final sx = cx - half + lx ~/ cell, sy = cy - half + ly ~/ cell;
      int b = 0x23, g = 0x1F, r = 0x1B; // outside the screen
      if (sx >= 0 && sy >= 0 && sx < src.w && sy < src.h) {
        final i = (sy * src.w + sx) * 4;
        b = src.bgra[i];
        g = src.bgra[i + 1];
        r = src.bgra[i + 2];
      }
      if (grid && (lx % cell == 0 || ly % cell == 0)) {
        // a faint grid between the pixels
        b -= b ~/ 6;
        g -= g ~/ 6;
        r -= r ~/ 6;
      }
      put(x, y, b, g, r);
    }
  }

  // The pixel under the cursor: a black frame inside a white one — seen on
  // any colour.
  final x0 = 1 + half * cell, y0 = 1 + half * cell, x1 = x0 + cell - 1, y1 = y0 + cell - 1;
  void ring(int a0, int b0, int a1, int b1, int v) {
    for (var x = a0; x <= a1; x++) {
      put(x, b0, v, v, v);
      put(x, b1, v, v, v);
    }
    for (var y = b0; y <= b1; y++) {
      put(a0, y, v, v, v);
      put(a1, y, v, v, v);
    }
  }

  ring(x0 - 1, y0 - 1, x1 + 1, y1 + 1, 255);
  ring(x0, y0, x1, y1, 0);
  return Bitmap(size, size, out);
}
