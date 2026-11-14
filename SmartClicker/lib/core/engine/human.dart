// Human-like randomness: Gaussian scatter and Bezier mouse paths.

import 'dart:math' as math;

/// Helpers that make input look less robotic.
class Human {
  final math.Random rng;
  Human(this.rng);

  /// Standard normal value (Box–Muller).
  double gauss() {
    final u1 = 1 - rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Offset within ±[radius], concentrated near the centre.
  int offset(num radius) {
    if (radius <= 0) return 0;
    final v = gauss() * radius / 2.5;
    return v.clamp(-radius, radius).round();
  }

  /// Multiplies [ms] by a factor around 1 with relative spread [jitter].
  num jitter(num ms, double jitter) {
    if (jitter <= 0) return ms;
    final f = 1 + (gauss() * jitter / 2).clamp(-jitter, jitter);
    return math.max(0, ms * f);
  }

  /// Natural-looking duration (ms) for a mouse move of [dist] pixels.
  int moveDuration(double dist) =>
      (90 + dist * 0.35 + rng.nextInt(90)).clamp(60, 900).round();

  /// Points from a to b. [curved] bends the path along a random Bézier arc
  /// with slow start and end; otherwise it is a straight, evenly-timed line.
  List<({int x, int y})> path(int x0, int y0, int x1, int y1, int steps,
      {bool curved = true}) {
    final out = <({int x, int y})>[];
    if (steps < 1) steps = 1;
    final dx = (x1 - x0).toDouble(), dy = (y1 - y0).toDouble();
    final dist = math.sqrt(dx * dx + dy * dy);
    var c1x = x0 + dx / 3, c1y = y0 + dy / 3;
    var c2x = x0 + dx * 2 / 3, c2y = y0 + dy * 2 / 3;
    if (curved && dist > 4) {
      // Push control points sideways, perpendicular to the line.
      final nx = -dy / dist, ny = dx / dist;
      final bend = dist * 0.18;
      final b1 = gauss() * bend, b2 = gauss() * bend;
      c1x += nx * b1;
      c1y += ny * b1;
      c2x += nx * b2;
      c2y += ny * b2;
    }
    for (var i = 1; i <= steps; i++) {
      var t = i / steps;
      if (curved) t = t * t * (3 - 2 * t); // ease in-out
      final u = 1 - t;
      final x = u * u * u * x0 + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * x1;
      final y = u * u * u * y0 + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * y1;
      out.add((x: x.round(), y: y.round()));
    }
    out[out.length - 1] = (x: x1, y: y1);
    return out;
  }
}
