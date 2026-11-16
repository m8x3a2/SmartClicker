// How much of a screen area changed between two captures — for wait_change
// (something appeared, a page loaded) and wait_still (an animation or text
// being typed has stopped).

import 'dart:typed_data';

/// The share (0..1) of pixels that differ between [a] and [b] (BGRA of the
/// same size) by more than [tolerance] (sum of the three channels). Big
/// areas are compared on every second pixel of every second row.
double changedShare(Uint8List a, Uint8List b, int w, int h, {int tolerance = 30}) {
  if (a.length != b.length || w <= 0 || h <= 0) return 1;
  final step = w * h > 400000 ? 2 : 1;
  var changed = 0, seen = 0;
  for (var y = 0; y < h; y += step) {
    final row = y * w * 4;
    for (var x = 0; x < w; x += step) {
      final i = row + x * 4;
      final d = (a[i] - b[i]).abs() + (a[i + 1] - b[i + 1]).abs() + (a[i + 2] - b[i + 2]).abs();
      if (d > tolerance) changed++;
      seen++;
    }
  }
  return seen == 0 ? 0 : changed / seen;
}
