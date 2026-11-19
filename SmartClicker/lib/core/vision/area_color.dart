// Colour of an area and comparing colours: average, median, main colour;
// hue, brightness, saturation (avg_color, color_diff, hue, brightness, watch).

import 'dart:math' as math;
import 'dart:typed_data';

/// The colour (0xRRGGBB) of BGRA pixels [bgra]:
/// 'avg' — average; 'median' — median of each channel (a cursor or a popup
/// over a part of the area does not shift it); 'main' — the most common
/// colour (similar shades counted together).
int areaColor(Uint8List bgra, {String mode = 'avg'}) {
  final n = bgra.length ~/ 4;
  if (n == 0) return 0;
  switch (mode) {
    case 'median':
      final hist = [List.filled(256, 0), List.filled(256, 0), List.filled(256, 0)];
      for (var i = 0; i < n; i++) {
        hist[0][bgra[i * 4 + 2]]++;
        hist[1][bgra[i * 4 + 1]]++;
        hist[2][bgra[i * 4]]++;
      }
      int med(List<int> h) {
        var acc = 0;
        for (var v = 0; v < 256; v++) {
          acc += h[v];
          if (acc * 2 >= n) return v;
        }
        return 255;
      }
      return (med(hist[0]) << 16) | (med(hist[1]) << 8) | med(hist[2]);
    case 'main':
      // 16 levels per channel; the average of the fullest bucket
      final count = <int, int>{}, sum = <int, List<int>>{};
      for (var i = 0; i < n; i++) {
        final b = bgra[i * 4], g = bgra[i * 4 + 1], r = bgra[i * 4 + 2];
        final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        count[key] = (count[key] ?? 0) + 1;
        final s = sum.putIfAbsent(key, () => [0, 0, 0]);
        s[0] += r;
        s[1] += g;
        s[2] += b;
      }
      var best = count.keys.first;
      for (final e in count.entries) {
        if (e.value > count[best]!) best = e.key;
      }
      final c = count[best]!, s = sum[best]!;
      return ((s[0] ~/ c) << 16) | ((s[1] ~/ c) << 8) | (s[2] ~/ c);
    default:
      var r = 0, g = 0, b = 0;
      for (var i = 0; i < n; i++) {
        b += bgra[i * 4];
        g += bgra[i * 4 + 1];
        r += bgra[i * 4 + 2];
      }
      return ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }
}

/// Brightness as the eye sees it, 0..255.
int brightnessOf(int rgb) {
  final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b).round();
}

/// Hue, 0..359 degrees (red 0, green 120, blue 240); 0 for greys.
int hueOf(int rgb) {
  final r = ((rgb >> 16) & 0xFF) / 255, g = ((rgb >> 8) & 0xFF) / 255, b = (rgb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  if (d < 1e-9) return 0;
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return ((h * 60).round() + 360) % 360;
}

/// Saturation, 0..100 (0 — grey, 100 — pure colour).
int saturationOf(int rgb) {
  final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  return mx == 0 ? 0 : ((mx - mn) * 100 / mx).round();
}

/// How different two colours are, [by]:
/// 'rgb' — the largest difference of a channel, 0..255;
/// 'hue' — difference of hue in degrees, 0..180 (shadows and light do not
///   change it; greys have no hue);
/// 'bright' — difference of brightness, 0..255.
int colorDistance(int a, int b, {String by = 'rgb'}) {
  switch (by) {
    case 'hue':
      final d = (hueOf(a) - hueOf(b)).abs() % 360;
      return d > 180 ? 360 - d : d;
    case 'bright':
      return (brightnessOf(a) - brightnessOf(b)).abs();
    default:
      final dr = ((a >> 16) & 0xFF) - ((b >> 16) & 0xFF);
      final dg = ((a >> 8) & 0xFF) - ((b >> 8) & 0xFF);
      final db = (a & 0xFF) - (b & 0xFF);
      return math.max(dr.abs(), math.max(dg.abs(), db.abs()));
  }
}
