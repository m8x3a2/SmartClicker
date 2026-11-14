// Scaled image search on the real screen: cuts pieces of the screen,
// resizes them and looks for them in the full screenshot.
//   dart run tool/smoke_scale.dart
// ignore_for_file: avoid_print
import 'package:smart_clicker/core/vision/image.dart';
import 'package:smart_clicker/platform/windows/windows_backend.dart';

Bitmap crop(Bitmap s, int x, int y, int w, int h) {
  final out = Bitmap(w, h, s.bgra.sublist(0, w * h * 4));
  for (var r = 0; r < h; r++) {
    out.bgra.setRange(r * w * 4, (r + 1) * w * 4, s.bgra, ((y + r) * s.w + x) * 4);
  }
  return out;
}

void main() {
  final b = WindowsBackend();
  final sz = b.screenSize();
  final screen = Bitmap(sz.w, sz.h, b.capture(0, 0, sz.w, sz.h));
  // the most detailed 120x60 pieces on a grid (sum of sharp brightness
  // steps between neighbours: text, icons; not smooth gradients)
  double spread(int x, int y) {
    var e = 0.0;
    for (var j = 0; j < 60; j++) {
      for (var i = 0; i < 119; i++) {
        final o = ((y + j) * sz.w + x + i) * 4;
        final dv = (screen.bgra[o + 1] - screen.bgra[o + 5]).abs();
        if (dv > 40) e += dv;
      }
    }
    return e;
  }

  final grid = [
    for (var y = 0; y + 60 <= sz.h; y += 60)
      for (var x = 0; x + 120 <= sz.w; x += 120) (x, y, spread(x, y)),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  final spots = grid.take(6).toList();
  var ok = 0, total = 0;
  for (final (x, y, _) in spots) {
    for (final k in [0.7, 0.85, 1.25, 1.6]) {
      // the screen piece is what is "on screen"; the needle is the piece
      // as it was cut at another size
      final piece = crop(screen, x, y, 120, 60);
      final needle = resize(piece, (120 / k).round(), (60 / k).round());
      final sw = Stopwatch()..start();
      final hit = findBitmapScaled(screen, needle);
      total++;
      final good = hit != null &&
          (hit.x + hit.w / 2 - (x + 60)).abs() <= 3 &&
          (hit.y + hit.h / 2 - (y + 30)).abs() <= 3;
      if (good) ok++;
      print('($x,$y) k=$k -> ${hit == null ? 'null' : '(${hit.x},${hit.y}) ${hit.w}x${hit.h} s=${hit.scale.toStringAsFixed(2)}'} '
          '${sw.elapsedMilliseconds} ms ${good ? 'OK' : 'MISS'}');
    }
  }
  print('$ok / $total');
}
