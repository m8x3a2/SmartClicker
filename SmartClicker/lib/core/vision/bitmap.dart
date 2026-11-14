// A picture in memory (BGRA pixels) and resizing it.

import 'dart:typed_data';

/// Top-down bitmap, 4 bytes per pixel: B, G, R, A.
class Bitmap {
  final int w, h;
  final Uint8List bgra;
  Bitmap(this.w, this.h, this.bgra);
}

/// Bilinear upscale by an integer factor (small text is recognized much
/// better when enlarged). Alpha becomes opaque.
Bitmap upscale(Bitmap s, int k) {
  if (k <= 1) return s;
  final w = s.w * k, h = s.h * k;
  final out = Uint8List(w * h * 4);
  final src = s.bgra;
  var o = 0;
  for (var y = 0; y < h; y++) {
    final fy = ((y + 0.5) / k - 0.5).clamp(0.0, s.h - 1.0);
    final y0 = fy.floor(), y1 = y0 + 1 < s.h ? y0 + 1 : y0;
    final wy = ((fy - y0) * 256).round();
    for (var x = 0; x < w; x++, o += 4) {
      final fx = ((x + 0.5) / k - 0.5).clamp(0.0, s.w - 1.0);
      final x0 = fx.floor(), x1 = x0 + 1 < s.w ? x0 + 1 : x0;
      final wx = ((fx - x0) * 256).round();
      final a = (y0 * s.w + x0) * 4, b = (y0 * s.w + x1) * 4;
      final c = (y1 * s.w + x0) * 4, e = (y1 * s.w + x1) * 4;
      for (var ch = 0; ch < 3; ch++) {
        final top = src[a + ch] * (256 - wx) + src[b + ch] * wx;
        final bot = src[c + ch] * (256 - wx) + src[e + ch] * wx;
        out[o + ch] = (top * (256 - wy) + bot * wy) >> 16;
      }
      out[o + 3] = 255;
    }
  }
  return Bitmap(w, h, out);
}

/// Resamples to [w]×[h]: every target pixel averages a grid of bilinear
/// samples, so shrinking does not alias and growing stays smooth. Alpha is
/// resampled too.
Bitmap resize(Bitmap s, int w, int h) {
  if (w == s.w && h == s.h) return s;
  final out = Uint8List(w * h * 4);
  final src = s.bgra;
  final fx = s.w / w, fy = s.h / h;
  final nx = fx.ceil().clamp(1, 8), ny = fy.ceil().clamp(1, 8);
  final acc = List<double>.filled(4, 0);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++, o += 4) {
      acc.fillRange(0, 4, 0);
      for (var j = 0; j < ny; j++) {
        final sy = ((y + (j + 0.5) / ny) * fy - 0.5).clamp(0.0, s.h - 1.0);
        final y0 = sy.floor(), y1 = y0 + 1 < s.h ? y0 + 1 : y0;
        final wy = sy - y0;
        for (var i = 0; i < nx; i++) {
          final sx = ((x + (i + 0.5) / nx) * fx - 0.5).clamp(0.0, s.w - 1.0);
          final x0 = sx.floor(), x1 = x0 + 1 < s.w ? x0 + 1 : x0;
          final wx = sx - x0;
          final a = (y0 * s.w + x0) * 4, b = (y0 * s.w + x1) * 4;
          final c = (y1 * s.w + x0) * 4, e = (y1 * s.w + x1) * 4;
          for (var ch = 0; ch < 4; ch++) {
            final top = src[a + ch] * (1 - wx) + src[b + ch] * wx;
            final bot = src[c + ch] * (1 - wx) + src[e + ch] * wx;
            acc[ch] += top * (1 - wy) + bot * wy;
          }
        }
      }
      final n = nx * ny;
      for (var ch = 0; ch < 4; ch++) {
        out[o + ch] = (acc[ch] / n).round().clamp(0, 255);
      }
    }
  }
  return Bitmap(w, h, out);
}
