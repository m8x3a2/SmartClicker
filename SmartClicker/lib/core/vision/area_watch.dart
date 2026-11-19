// watch(): what to wait for in an area ("изменилась", "стала #цвет",
// "светлее 120", "не меняется 10s") and one check of it. Pure logic; the
// runtime takes the pictures and runs the reaction.

import 'dart:typed_data';

import 'area_color.dart';
import 'frame_diff.dart';

/// A parsed `when:` of watch.
class WatchRule {
  /// 'changed' | 'color' | 'brighter' | 'darker' | 'still'
  final String kind;
  final int color, level, ms;
  const WatchRule(this.kind, {this.color = 0, this.level = 0, this.ms = 0});

  @override
  String toString() => switch (kind) {
        'color' => 'стала #${color.toRadixString(16).padLeft(6, '0').toUpperCase()}',
        'brighter' => 'светлее $level',
        'darker' => 'темнее $level',
        'still' => 'не меняется ${ms ~/ 1000} с',
        _ => 'изменилась',
      };
}

final _hex = RegExp(r'#([0-9a-fA-F]{6})');
final _number = RegExp(r'(\d+(?:[.,]\d+)?)\s*(ms|мс|s|с|сек|m|мин|м|h|ч)?');

/// `when:` → a rule; null when it is not understood.
WatchRule? parseWatchRule(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || const {'changed', 'change', 'изменилась', 'изменится', 'изменение'}.contains(t)) {
    return const WatchRule('changed');
  }
  final hex = _hex.firstMatch(t);
  if (hex != null) return WatchRule('color', color: int.parse(hex[1]!, radix: 16));
  final n = _number.firstMatch(t);
  if (t.startsWith('светлее') || t.startsWith('brighter')) {
    return n == null ? null : WatchRule('brighter', level: double.parse(n[1]!.replaceAll(',', '.')).round());
  }
  if (t.startsWith('темнее') || t.startsWith('darker')) {
    return n == null ? null : WatchRule('darker', level: double.parse(n[1]!.replaceAll(',', '.')).round());
  }
  if (t.startsWith('не меня') || t.startsWith('still') || t.startsWith('замерл')) {
    if (n == null) return const WatchRule('still', ms: 1000);
    final v = double.parse(n[1]!.replaceAll(',', '.'));
    final unit = n[2] ?? 's';
    final ms = switch (unit) {
      'ms' || 'мс' => v,
      'm' || 'мин' || 'м' => v * 60000,
      'h' || 'ч' => v * 3600000,
      _ => v * 1000,
    };
    return WatchRule('still', ms: ms.round());
  }
  return null;
}

/// What one watch remembers between checks.
class WatchState {
  Uint8List? ref, prev;
  bool was = false;
  int stillSince = 0;

  /// The colour of the area at the last check (passed to the reaction).
  int lastColor = 0;
}

/// One check of [rule] with the area now ([now], [w]×[h] BGRA) at [nowMs].
/// True — the reaction runs: the condition has just become true ("changed"
/// — the area differs from how it was when watching started or after the
/// last time; colour and brightness — when they first match).
bool watchStep(WatchRule rule, WatchState st, Uint8List now, int w, int h, int nowMs,
    {int tolerance = 20, num percent = 2, String mode = 'median'}) {
  st.lastColor = areaColor(now, mode: mode);
  switch (rule.kind) {
    case 'changed':
      final ref = st.ref;
      if (ref == null) {
        st.ref = now;
        return false;
      }
      if (pictureDiff(ref, now, w, h, tolerance: tolerance) * 100 <= percent) return false;
      st.ref = now; // the next time: changed against this
      return true;
    case 'still':
      final prev = st.prev;
      if (prev == null || pictureDiff(prev, now, w, h, tolerance: tolerance) * 100 > percent) {
        st.stillSince = nowMs;
      }
      st.prev = now;
      return _edge(st, nowMs - st.stillSince >= rule.ms);
    case 'color':
      return _edge(st, colorDistance(st.lastColor, rule.color) <= tolerance);
    case 'brighter':
      return _edge(st, brightnessOf(st.lastColor) > rule.level);
    case 'darker':
      return _edge(st, brightnessOf(st.lastColor) < rule.level);
  }
  return false;
}

bool _edge(WatchState st, bool cond) {
  final fire = cond && !st.was;
  st.was = cond;
  return fire;
}
