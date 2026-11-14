// Searching a picture on the screen: exact place with a colour tolerance, and in
// another scale (brightness correlation, anchor colours, refining the size).

import 'dart:math' as math;
import 'dart:typed_data';
import 'bitmap.dart';

/// Finds [needle] inside [hay]. A pixel matches when every channel differs
/// by at most [tolerance]; up to [badShare] of the pixels may differ.
/// Transparent pixels of the needle match anything. Returns the top-left
/// corner of the first match (rows top to bottom).
({int x, int y})? findBitmap(Bitmap hay, Bitmap needle,
    {int tolerance = 20, double badShare = 0.02, bool smoothProbes = false}) {
  final m = _Matcher.of(hay, needle, tolerance, badShare, smoothProbes);
  if (m == null) return null;
  for (var y = 0; y <= hay.h - needle.h; y++) {
    for (var x = 0; x <= hay.w - needle.w; x++) {
      if (m.at(x, y)) return (x: x, y: y);
    }
  }
  return null;
}

/// Checks one placement of a needle: a few spread-out probe pixels first,
/// then all opaque pixels with a budget of differing ones.
class _Matcher {
  final Bitmap hay, needle;
  final int tolerance, allowed;
  final Int32List probeHay, probeNeedle, allHay, allNeedle;

  _Matcher._(this.hay, this.needle, this.tolerance, this.allowed,
      this.probeHay, this.probeNeedle, this.allHay, this.allNeedle);

  static _Matcher? of(Bitmap hay, Bitmap needle, int tolerance,
      double badShare, bool smoothProbes) {
    final nw = needle.w, nh = needle.h;
    if (nw <= 0 || nh <= 0 || nw > hay.w || nh > hay.h) return null;
    final opaque = _opaque(needle);
    if (opaque.isEmpty) return null;
    // After resampling, pixels on sharp edges change a lot, so flat ones
    // make better probes.
    var pool = opaque;
    if (smoothProbes) {
      final flat = opaque.where((p) => _flat(needle, p)).toList();
      if (flat.length >= 12) pool = flat;
    }
    final probes = [
      for (var k = 0; k < 12; k++) pool[(pool.length - 1) * k ~/ 11],
    ];
    int off(int p) => ((p ~/ nw) * hay.w + p % nw) * 4;
    return _Matcher._(
      hay,
      needle,
      tolerance,
      (opaque.length * badShare).floor(),
      Int32List.fromList([for (final p in probes) off(p)]),
      Int32List.fromList([for (final p in probes) p * 4]),
      Int32List.fromList([for (final p in opaque) off(p)]),
      Int32List.fromList([for (final p in opaque) p * 4]),
    );
  }

  /// The needle placed with its top-left corner at ([x], [y]) matches.
  bool at(int x, int y) {
    if (x < 0 || y < 0 || x + needle.w > hay.w || y + needle.h > hay.h) {
      return false;
    }
    final s = hay.bgra, n = needle.bgra, t = tolerance;
    final base = (y * hay.w + x) * 4;
    for (var k = 0; k < probeHay.length; k++) {
      final hi = base + probeHay[k], ni = probeNeedle[k];
      if ((s[hi] - n[ni]).abs() > t ||
          (s[hi + 1] - n[ni + 1]).abs() > t ||
          (s[hi + 2] - n[ni + 2]).abs() > t) {
        return false;
      }
    }
    var bad = 0;
    for (var k = 0; k < allHay.length; k++) {
      final hi = base + allHay[k], ni = allNeedle[k];
      if ((s[hi] - n[ni]).abs() > t ||
          (s[hi + 1] - n[ni + 1]).abs() > t ||
          (s[hi + 2] - n[ni + 2]).abs() > t) {
        if (++bad > allowed) return false;
      }
    }
    return true;
  }
}

List<int> _opaque(Bitmap b) => [
      for (var i = 0; i < b.w * b.h; i++)
        if (b.bgra[i * 4 + 3] >= 128) i,
    ];

/// True when the pixel and its four neighbours are nearly the same colour.
bool _flat(Bitmap b, int p) {
  final x = p % b.w, y = p ~/ b.w;
  if (x == 0 || y == 0 || x == b.w - 1 || y == b.h - 1) return false;
  final d = b.bgra;
  for (final q in [p - 1, p + 1, p - b.w, p + b.w]) {
    for (var ch = 0; ch < 3; ch++) {
      if ((d[p * 4 + ch] - d[q * 4 + ch]).abs() > 12) return false;
    }
  }
  return true;
}

/// Mean channel difference over the opaque needle pixels at ([x], [y]);
/// stops early once it is certain to exceed [limit].
double _score(Bitmap hay, Bitmap n, List<int> opaque, int x, int y,
    double limit) {
  final s = hay.bgra, d = n.bgra;
  final stop = limit * opaque.length * 3;
  var sum = 0;
  for (final p in opaque) {
    final hi = ((y + p ~/ n.w) * hay.w + x + p % n.w) * 4, ni = p * 4;
    sum += (s[hi] - d[ni]).abs() +
        (s[hi + 1] - d[ni + 1]).abs() +
        (s[hi + 2] - d[ni + 2]).abs();
    if (sum > stop) return double.infinity;
  }
  return sum / (opaque.length * 3);
}

/// Scales of the needle between [minScale] and [maxScale], nearest to
/// [center] (default: 1, or the nearest bound) first. The larger side of
/// neighbouring sizes differs by a pixel (1.5% on big sizes); both bounds
/// are included.
List<double> searchScales(int w, int h, double minScale, double maxScale,
    {double? center}) {
  final big = w > h ? w : h;
  final c = (center ?? 1.0).clamp(minScale, maxScale);
  final lo = (big * minScale).round(), hi = (big * maxScale).round();
  final start = (big * c).round().clamp(lo, hi);
  int gap(int size) => (size * 0.015).round().clamp(1, 1 << 20);
  final up = <int>[start], down = <int>[];
  for (var v = start + gap(start); v < hi; v += gap(v)) {
    up.add(v);
  }
  if (up.last != hi) up.add(hi);
  for (var v = start - gap(start); v > lo; v -= gap(v)) {
    down.add(v);
  }
  if (start != lo) down.add(lo);
  final out = <double>[];
  final seen = <int>{};
  for (var i = 0; i < up.length || i < down.length; i++) {
    for (final v in [if (i < up.length) up[i], if (i < down.length) down[i]]) {
      final k = v == start ? c : v / big;
      final nw = (w * k).round(), nh = (h * k).round();
      if (nw < 3 || nh < 3) continue;
      if (seen.add(nw * 100000 + nh)) out.add(k);
    }
  }
  return out;
}

typedef ScaledHit = ({int x, int y, int w, int h, double scale});

/// Finds [needle] drawn at another scale (between [minScale] and
/// [maxScale], sizes nearest to [center] tried first).
///
/// Colours may differ a little after resampling, so the colour check is
/// loose (difference up to [tolerance] + 25, 15% of pixels may differ);
/// the brightness pattern has to match too (normalised correlation ≥ 0.7),
/// or text on a plain background would match any empty place of that
/// background. The size and position are refined by the mean colour
/// difference.
///
/// Speed: big needles are first looked for in a shrunk copy of the screen
/// (the brightness pattern survives shrinking, fine resampling differences
/// do not matter there); the best places are then checked at full size.
/// Small needles: flat areas keep their colour at any scale, so for every
/// size the flat colour of the needle that is rarest on the screen becomes
/// an anchor, and only the places where it occurs are checked.
ScaledHit? findBitmapScaled(Bitmap hay, Bitmap needle,
    {int tolerance = 20,
    double minScale = 0.5,
    double maxScale = 2,
    double? center}) {
  final scales =
      searchScales(needle.w, needle.h, minScale, maxScale, center: center);
  final sorted = [...scales]..sort();
  final cache = <double, Bitmap>{};
  Bitmap sized(double k) => cache[k] ??=
      resize(needle, (needle.w * k).round(), (needle.h * k).round());
  final loose = tolerance + 25;
  final lum = _LumTable.of(hay);
  final stats = <Bitmap, _NeedleLum>{};
  bool verify(Bitmap m, int x, int y) =>
      _loosePass(hay, m, x, y, loose) &&
      lum.correlation(stats[m] ??= _NeedleLum(m), x, y) >= 0.7;
  int nearest(double k) {
    var j = 0;
    for (var i = 1; i < sorted.length; i++) {
      if ((sorted[i] - k).abs() < (sorted[j] - k).abs()) j = i;
    }
    return j;
  }

  // The original size: exact search first.
  if (minScale <= 1 && maxScale >= 1 && needle.w <= hay.w && needle.h <= hay.h) {
    final p = findBitmap(hay, needle, tolerance: tolerance);
    if (p != null) {
      return (x: p.x, y: p.y, w: needle.w, h: needle.h, scale: 1.0);
    }
  }

  final small = math.min(needle.w, needle.h) * minScale;
  final f = (small / 8).floor().clamp(1, 8);
  if (f >= 2 &&
      hay.w ~/ f >= 8 &&
      hay.h ~/ f >= 8 &&
      !_NeedleLum(resize(needle, needle.w ~/ f, needle.h ~/ f)).flat) {
    final lo = _LumTable.of(hay, f);
    final seen = <int>{};
    // (correlation, scale, centre x, centre y) at full size
    final found = <(double, double, double, double)>[];
    final tried = <int>{};
    var refines = 0;
    ScaledHit? refineAt(double k, double cx, double cy) {
      if (refines >= 12) return null;
      if (!tried.add((cx ~/ (2 * f)) * 100000 + cy ~/ (2 * f))) return null;
      refines++;
      return _refine(hay, sorted, nearest(k), sized, cx, cy, f + 1, verify);
    }

    // Shrunk, neighbouring sizes look alike: steps of about 4% are enough.
    final kept = <double>[];
    for (final k in searchScales((needle.w / f).round(), (needle.h / f).round(),
        minScale, maxScale, center: center)) {
      if (kept.any((q) => (k / q - 1).abs() < 0.035)) continue;
      kept.add(k);
      final w = (needle.w * k / f).round(), h = (needle.h * k / f).round();
      if (w > lo.w || h > lo.h || !seen.add(w * 100000 + h)) continue;
      final ns = _NeedleLum(resize(needle, w, h));
      (double, double, double, double)? best;
      for (var y = 0; y <= lo.h - h; y++) {
        for (var x = 0; x <= lo.w - w; x++) {
          if (lo.correlation(ns, x, y, sparse: true) < 0.5) continue;
          final c = lo.correlation(ns, x, y);
          if (c < 0.7) continue;
          final cand = (c, k, (x + w / 2) * f, (y + h / 2) * f);
          found.add(cand);
          if (best == null || c > best.$1) best = cand;
        }
      }
      // a very strong match: check it at once
      if (best != null && best.$1 >= 0.9) {
        final hit = refineAt(best.$2, best.$3, best.$4);
        if (hit != null) return hit;
      }
    }
    // The best places first; a place (and its neighbourhood) once.
    found.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, k, cx, cy) in found) {
      final hit = refineAt(k, cx, cy);
      if (hit != null) return hit;
      if (refines >= 12) break;
    }
    return null;
  }

  final anchors = _anchors(hay, needle, tolerance + 10);
  for (final k in scales) {
    final n = sized(k);
    if (n.w > hay.w || n.h > hay.h) continue;
    final m = _Matcher.of(hay, n, loose, 0.15, true);
    if (m == null) continue;
    final ns = stats[n] ??= _NeedleLum(n);
    final refined = <int>{};

    ScaledHit? tryAt(int x, int y) {
      if (x < 0 || y < 0 || x + n.w > hay.w || y + n.h > hay.h) return null;
      if (lum.plainFor(ns, x, y) || !m.at(x, y)) return null;
      if (lum.correlation(ns, x, y) < 0.7) return null;
      // neighbouring places lead to the same refinement: do it once
      if (!refined.add((x ~/ 3) * 100000 + y ~/ 3)) return null;
      return _refine(hay, sorted, sorted.indexOf(k), sized, x + n.w / 2,
          y + n.h / 2, 2, verify);
    }

    // the rarest anchor colour that is still flat at this size
    ({int x, int y})? a;
    _Anchor? anchor;
    for (final c in anchors) {
      a = _anchorIn(n, c.color, 1 + k.ceil());
      if (a != null) {
        anchor = c;
        break;
      }
    }
    if (anchor != null && a != null) {
      final spots = anchor.spots;
      for (var i = 0; i < spots.length; i++) {
        final hit = tryAt(spots[i] % hay.w - a.x, spots[i] ~/ hay.w - a.y);
        if (hit != null) return hit;
      }
    } else {
      // no usable anchor: every position
      for (var y = 0; y <= hay.h - n.h; y++) {
        for (var x = 0; x <= hay.w - n.w; x++) {
          final hit = tryAt(x, y);
          if (hit != null) return hit;
        }
      }
    }
  }
  return null;
}

/// Brightness of a BGRA pixel at byte offset [o], 0..255.
int _lumAt(Uint8List d, int o) => (d[o] * 29 + d[o + 1] * 150 + d[o + 2] * 77) >> 8;

/// Brightness of the opaque needle pixels, their mean and spread.
class _NeedleLum {
  final Bitmap n;
  late final Int32List offsets; // pixel index in the needle
  late final Float64List centred; // brightness minus the mean
  late final double norm; // sqrt of the sum of squares of [centred]
  late final bool opaque;

  /// 32 indexes into [offsets] for a fast rough correlation: spread over
  /// the pixels ordered by how far they are from the mean brightness.
  late final Int32List probes = () {
    final order = List<int>.generate(offsets.length, (i) => i)
      ..sort((a, b) => centred[b].abs().compareTo(centred[a].abs()));
    final cnt = math.min(32, order.length);
    return Int32List.fromList(
        [for (var i = 0; i < cnt; i++) order[(order.length - 1) * i ~/ math.max(1, cnt - 1)]]);
  }();

  _NeedleLum(this.n) {
    final idx = _opaque(n);
    offsets = Int32List.fromList(idx);
    opaque = idx.length == n.w * n.h;
    var sum = 0.0;
    for (final p in idx) {
      sum += _lumAt(n.bgra, p * 4);
    }
    final mean = idx.isEmpty ? 0.0 : sum / idx.length;
    centred = Float64List(idx.length);
    var sq = 0.0;
    for (var i = 0; i < idx.length; i++) {
      final v = _lumAt(n.bgra, idx[i] * 4) - mean;
      centred[i] = v;
      sq += v * v;
    }
    norm = math.sqrt(sq);
  }

  /// Nearly one colour: the brightness pattern says nothing.
  bool get flat => offsets.isEmpty || norm / math.sqrt(offsets.length) < 4;
}

/// Summed-area tables of a brightness image (the haystack, possibly
/// shrunk): the mean and spread of any rectangle in constant time.
class _LumTable {
  final int w, h;
  final Uint8List lum;
  late final Float64List sum, sq;

  _LumTable(this.lum, this.w, this.h) {
    final tw = w + 1;
    sum = Float64List(tw * (h + 1));
    sq = Float64List(tw * (h + 1));
    for (var y = 0; y < h; y++) {
      var rs = 0.0, rq = 0.0;
      for (var x = 0; x < w; x++) {
        final v = lum[y * w + x].toDouble();
        rs += v;
        rq += v * v;
        final i = (y + 1) * tw + x + 1;
        sum[i] = sum[i - tw] + rs;
        sq[i] = sq[i - tw] + rq;
      }
    }
  }

  /// Brightness of [b], shrunk [f] times (mean of f×f blocks).
  factory _LumTable.of(Bitmap b, [int f = 1]) {
    final w = b.w ~/ f, h = b.h ~/ f;
    final out = Uint8List(w * h);
    final d = b.bgra, area = f * f;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0;
        for (var j = 0; j < f; j++) {
          var o = ((y * f + j) * b.w + x * f) * 4;
          for (var i = 0; i < f; i++, o += 4) {
            s += _lumAt(d, o);
          }
        }
        out[y * w + x] = s ~/ area;
      }
    }
    return _LumTable(out, w, h);
  }

  double _rect(Float64List t, int x, int y, int rw, int rh) {
    final tw = w + 1;
    return t[(y + rh) * tw + x + rw] - t[y * tw + x + rw] -
        t[(y + rh) * tw + x] + t[y * tw + x];
  }

  /// Quick rejection in constant time: the place under an opaque needle
  /// with a pattern is much plainer than the needle.
  bool plainFor(_NeedleLum n, int x, int y) {
    if (n.flat || !n.opaque) return false;
    final nw = n.n.w, nh = n.n.h;
    final s = _rect(sum, x, y, nw, nh), q = _rect(sq, x, y, nw, nh);
    final varSum = q - s * s / n.offsets.length;
    return varSum <= 0 || math.sqrt(varSum) < n.norm * 0.3;
  }

  /// Normalised cross-correlation of the needle brightness with the image
  /// at ([x], [y]): 1 — the same pattern, 0 — unrelated. A flat needle
  /// always gives 1 (nothing to compare). With [sparse], only a few
  /// telling pixels are used: a rough but fast estimate.
  double correlation(_NeedleLum n, int x, int y, {bool sparse = false}) {
    if (n.flat) return 1;
    if (plainFor(n, x, y)) return 0;
    final nw = n.n.w;
    final idx = sparse ? n.probes : null;
    final cnt = idx?.length ?? n.offsets.length;
    var hs = 0.0, hq = 0.0, cross = 0.0, ns = 0.0, nq = 0.0;
    for (var i = 0; i < cnt; i++) {
      final k = idx == null ? i : idx[i];
      final p = n.offsets[k];
      final v = lum[(y + p ~/ nw) * w + x + p % nw].toDouble();
      final c = n.centred[k];
      hs += v;
      hq += v * v;
      cross += v * c;
      ns += c;
      nq += c * c;
    }
    final hv = hq - hs * hs / cnt;
    final nv = nq - ns * ns / cnt;
    if (hv <= 0 || nv <= 0) return 0;
    return (cross - hs * ns / cnt) / math.sqrt(hv * nv);
  }
}

/// A flat colour of the needle and the screen pixels of nearly that colour.
class _Anchor {
  final Bitmap hay;
  final int color, tolerance;
  late final int count = _scan(null);
  late final Int32List spots = () {
    final out = Int32List(count);
    _scan(out);
    return out;
  }();

  _Anchor(this.hay, this.color, this.tolerance);

  int _scan(Int32List? out) {
    final s = hay.bgra, total = hay.w * hay.h, t = tolerance;
    final b = color & 0xFF, g = color >> 8 & 0xFF, r = color >> 16 & 0xFF;
    var n = 0;
    for (var i = 0, o = 0; i < total; i++, o += 4) {
      if ((s[o] - b).abs() <= t &&
          (s[o + 1] - g).abs() <= t &&
          (s[o + 2] - r).abs() <= t) {
        out?[n] = i;
        n++;
      }
    }
    return n;
  }
}

/// Up to six flat colours of [needle] (the most common first), sorted by
/// how rarely they occur in [hay]. Colours covering a quarter of the screen
/// are useless and left out.
List<_Anchor> _anchors(Bitmap hay, Bitmap needle, int tolerance) {
  final d = needle.bgra;
  final groups = <int, int>{}; // coarse colour -> pixel count
  final sample = <int, int>{}; // coarse colour -> exact colour
  for (final p in _opaque(needle)) {
    if (!_flat(needle, p)) continue;
    final o = p * 4;
    final key = d[o] >> 4 | (d[o + 1] >> 4) << 4 | (d[o + 2] >> 4) << 8;
    groups[key] = (groups[key] ?? 0) + 1;
    sample[key] ??= d[o] | d[o + 1] << 8 | d[o + 2] << 16;
  }
  final keys = groups.keys.toList()
    ..sort((a, b) => groups[b]!.compareTo(groups[a]!));
  final limit = hay.w * hay.h ~/ 4;
  return [
    for (final k in keys.take(6)) _Anchor(hay, sample[k]!, tolerance),
  ].where((a) => a.count <= limit).toList()
    ..sort((a, b) => a.count.compareTo(b.count));
}

/// A pixel of [n] of nearly [color] whose whole neighbourhood within
/// [radius] is that colour too (a resampled picture is blurred, so a pixel
/// that is merely flat may lie on a soft edge), nearest to the centre.
({int x, int y})? _anchorIn(Bitmap n, int color, int radius) {
  final b = color & 0xFF, g = color >> 8 & 0xFF, r = color >> 16 & 0xFF;
  final d = n.bgra;
  bool near(int o) =>
      d[o + 3] >= 128 &&
      (d[o] - b).abs() <= 10 &&
      (d[o + 1] - g).abs() <= 10 &&
      (d[o + 2] - r).abs() <= 10;
  ({int x, int y})? best;
  var bestDist = 1 << 30;
  for (var y = radius; y < n.h - radius; y++) {
    next:
    for (var x = radius; x < n.w - radius; x++) {
      final dist = (2 * x - n.w) * (2 * x - n.w) + (2 * y - n.h) * (2 * y - n.h);
      if (dist >= bestDist || !near((y * n.w + x) * 4)) continue;
      for (var j = -radius; j <= radius; j++) {
        for (var i = -radius; i <= radius; i++) {
          if (!near(((y + j) * n.w + x + i) * 4)) continue next;
        }
      }
      bestDist = dist;
      best = (x: x, y: y);
    }
  }
  return best;
}

/// Best position and size around the centre ([cx], [cy]), starting with
/// the scales next to `sorted[at]` and moving on while the mean colour
/// difference keeps falling; null when the best one does not really match.
ScaledHit? _refine(Bitmap hay, List<double> sorted, int at,
    Bitmap Function(double) sized, double cx, double cy, int radius,
    bool Function(Bitmap m, int x, int y) verify) {
  ScaledHit? best;
  var bestScore = double.infinity;
  var bestJ = at;
  void eval(int j) {
    if (j < 0 || j >= sorted.length) return;
    final m = sized(sorted[j]);
    final op = _opaque(m);
    if (op.isEmpty) return;
    final x0 = (cx - m.w / 2).round(), y0 = (cy - m.h / 2).round();
    for (var y = y0 - radius; y <= y0 + radius; y++) {
      for (var x = x0 - radius; x <= x0 + radius; x++) {
        if (x < 0 || y < 0 || x + m.w > hay.w || y + m.h > hay.h) continue;
        final sc = _score(hay, m, op, x, y, bestScore);
        if (sc < bestScore) {
          bestScore = sc;
          best = (x: x, y: y, w: m.w, h: m.h, scale: sorted[j]);
          bestJ = j;
        }
      }
    }
  }

  for (var j = at - 2; j <= at + 2; j++) {
    eval(j);
  }
  var lo = at - 2, hi = at + 2; // evaluated index range
  // the best size is at an edge of the evaluated range: look further
  for (var step = 0; step < 40; step++) {
    if (bestJ <= lo && lo > 0) {
      eval(--lo);
    } else if (bestJ >= hi && hi < sorted.length - 1) {
      eval(++hi);
    } else {
      break;
    }
  }
  final found = best;
  if (found == null) return null;
  return verify(sized(found.scale), found.x, found.y) ? found : null;
}

/// At most 15% of the opaque pixels differ by more than [tolerance].
bool _loosePass(Bitmap hay, Bitmap n, int x, int y, int tolerance) {
  final op = _opaque(n);
  final allowed = op.length * 0.15;
  final s = hay.bgra, d = n.bgra;
  var bad = 0;
  for (final p in op) {
    final hi = ((y + p ~/ n.w) * hay.w + x + p % n.w) * 4, ni = p * 4;
    if ((s[hi] - d[ni]).abs() > tolerance ||
        (s[hi + 1] - d[ni + 1]).abs() > tolerance ||
        (s[hi + 2] - d[ni + 2]).abs() > tolerance) {
      if (++bad > allowed) return false;
    }
  }
  return true;
}
