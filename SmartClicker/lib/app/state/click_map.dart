// The click map of a test run (no clicks): a screenshot taken at the first
// action and every action the script would have done, numbered.

import 'dart:typed_data';

class MapAction {
  final int n; // number on the map (1, 2, …)
  final String what;
  final int line;
  final int? x, y;

  /// 'press' (click, hold, drag…), 'move' (cursor, wheel), 'miss' (a
  /// picture to click was not found) or 'key' (keyboard: no point).
  final String kind;

  /// The line belongs to a script started with run_script.
  final bool other;
  const MapAction(this.n, this.what, this.line, this.x, this.y, this.kind, {this.other = false});

  bool get hasPoint => x != null && y != null;

  /// From an 'act' event of the engine.
  factory MapAction.of(int n, Map<String, Object?> e) {
    final x = (e['x'] as num?)?.toInt(), y = (e['y'] as num?)?.toInt();
    final k = '${e['k'] ?? 'press'}';
    return MapAction(n, '${e['m'] ?? ''}', (e['l'] as num?)?.toInt() ?? 0, x, y,
        x == null && k == 'press' ? 'key' : k,
        other: e['other'] == true);
  }
}

class ClickMap {
  final String script;
  final DateTime at;

  /// The screen at the first action: BGRA, opaque, [w]×[h].
  final int w, h;
  final Uint8List bgra;
  final List<MapAction> actions;

  /// All actions of the run (only the first ones are on the map).
  final int total;
  const ClickMap(this.script, this.at, this.w, this.h, this.bgra, this.actions, this.total);

  /// Actions with a point: the numbered circles on the screenshot.
  Iterable<MapAction> get points => actions.where((a) => a.hasPoint);
}

/// A screen capture (BitBlt leaves alpha 0) made opaque for showing.
Uint8List opaque(Uint8List bgra) {
  final out = Uint8List.fromList(bgra);
  for (var i = 3; i < out.length; i += 4) {
    out[i] = 255;
  }
  return out;
}
