// Where a picture of the files folder was cut from (screen px): kept inside
// the PNG itself, so it survives renaming and sharing. Used by same() /
// region_diff() without coordinates and shown on the «Pictures» page.

import 'dart:typed_data';

import 'png.dart';

const _originKey = 'SmartClicker.origin';

/// tEXt chunk for pngEncode(text:) — the region the picture was cut from.
Map<String, String> originText(int x, int y, int w, int h) => {_originKey: '$x,$y,$w,$h'};

/// The region a PNG was cut from, or null (an outside picture, an older one).
({int x, int y, int w, int h})? pictureOrigin(Uint8List png) {
  final v = pngText(png)[_originKey];
  if (v == null) return null;
  final n = v.split(',').map((s) => int.tryParse(s.trim())).toList();
  if (n.length != 4 || n.any((e) => e == null) || n[2]! <= 0 || n[3]! <= 0) return null;
  return (x: n[0]!, y: n[1]!, w: n[2]!, h: n[3]!);
}
