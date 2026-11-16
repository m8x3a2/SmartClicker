// Every place of a picture on the screen (find_images): all matches without
// near-duplicates of the same copy, in reading order.
part of 'image_search.dart';

/// All places of [needle] in [hay] at its own size, at most [max].
/// A blurred copy matches a pixel or two around its place too: matches
/// closer than half the picture size to an accepted one are the same copy.
List<ScaledHit> findAllBitmap(Bitmap hay, Bitmap needle,
    {int tolerance = 20, int max = 100}) {
  final m = _Matcher.of(hay, needle, tolerance, 0.02, false);
  if (m == null) return [];
  final pattern = _PatternCheck(hay, needle);
  return _readingOrder(
      _allPlaces(hay, needle, m, max, 1.0, const [], verify: pattern.ok), needle.h);
}

/// Like [findAllBitmap], but the picture may be drawn at another scale
/// (see [findBitmapScaled]). The scale is found by the best copy; the other
/// copies are looked for at that same size.
List<ScaledHit> findAllBitmapScaled(Bitmap hay, Bitmap needle,
    {int tolerance = 20,
    double minScale = 0.5,
    double maxScale = 2,
    double? center,
    int max = 100}) {
  final first = findBitmapScaled(hay, needle,
      tolerance: tolerance, minScale: minScale, maxScale: maxScale, center: center);
  if (first == null) return [];
  if (first.w == needle.w && first.h == needle.h) {
    final exact = findAllBitmap(hay, needle, tolerance: tolerance, max: max);
    if (exact.isNotEmpty) return exact;
  }
  final n = resize(needle, first.w, first.h);
  // the same loose check as the scaled search: colours and brightness pattern
  final m = _Matcher.of(hay, n, tolerance + 25, 0.15, true);
  if (m == null) return [first];
  final lum = _LumTable.of(hay);
  final ns = _NeedleLum(n);
  bool verify(int x, int y) => lum.correlation(ns, x, y) >= 0.7;
  return _readingOrder(
      _allPlaces(hay, n, m, max, first.scale, [first], verify: verify), n.h);
}

/// Scans every position row by row; the first match of a copy is kept and
/// the positions around it (closer than half the size) are skipped.
List<ScaledHit> _allPlaces(Bitmap hay, Bitmap n, _Matcher m, int max,
    double scale, List<ScaledHit> known,
    {bool Function(int x, int y)? verify}) {
  final out = <ScaledHit>[];
  final halfW = math.max(1, (n.w + 1) ~/ 2), halfH = math.max(1, (n.h + 1) ~/ 2);
  final cw = hay.w - n.w + 1, ch = hay.h - n.h + 1;
  final taken = Uint8List(cw * ch); // positions belonging to a found copy
  void take(ScaledHit h) {
    out.add(h);
    for (var y = math.max(0, h.y - halfH + 1); y < math.min(ch, h.y + halfH); y++) {
      taken.fillRange(y * cw + math.max(0, h.x - halfW + 1), y * cw + math.min(cw, h.x + halfW), 1);
    }
  }

  for (final h in known) {
    if (h.x < cw && h.y < ch) take(h);
  }
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      if (taken[y * cw + x] != 0 || !m.at(x, y)) continue;
      if (verify != null && !verify(x, y)) continue;
      if (out.length >= max) return out;
      take((x: x, y: y, w: n.w, h: n.h, scale: scale));
    }
  }
  return out;
}

/// Top to bottom; places whose tops differ by less than half the height
/// are one row, left to right.
List<ScaledHit> _readingOrder(List<ScaledHit> hits, int h) {
  final byY = [...hits]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  final out = <ScaledHit>[];
  var i = 0;
  while (i < byY.length) {
    var j = i + 1;
    while (j < byY.length && byY[j].y - byY[i].y < (h + 1) ~/ 2) {
      j++;
    }
    out.addAll(byY.sublist(i, j)..sort((a, b) => a.x.compareTo(b.x)));
    i = j;
  }
  return out;
}
