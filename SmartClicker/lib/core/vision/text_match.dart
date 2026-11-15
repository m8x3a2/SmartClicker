// Loose comparison of recognized text with the expected one: recognition
// mistakes a letter or two ("Враv" instead of "враг"), so a few wrong,
// missing or extra letters are allowed (similar, similarity, errors:).

import 'dart:math' as math;

import 'ocr.dart' show looseText;

/// How [text] and [pattern] are compared.
class MatchRules {
  /// Letters that may be wrong, missing or extra; null — 1 per 4 letters
  /// of the pattern ([autoErrors]).
  final int? errors;

  /// Instead of [errors]: how many percent of the pattern must match.
  final num? percent;

  /// Capital and small letters differ.
  final bool exactCase;

  /// The pattern may be a part of the text ("Начать" in "Начать игру").
  final bool part;

  /// Latin letters that look like Cyrillic ones are the same ("Р" and "P").
  final bool lookalike;

  const MatchRules(
      {this.errors, this.percent, this.exactCase = false, this.part = true, this.lookalike = true});
}

/// Allowed mistakes when none are given: 1 per 4 letters ("враг" — 1,
/// "Начать" — 1, "Переподключиться" — 4), none for 1–3 letters.
int autoErrors(int letters) => letters ~/ 4;

String _prepare(String s, MatchRules r) {
  if (!r.exactCase) {
    return r.lookalike ? looseText(s) : s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  final spaced = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (!r.lookalike) return spaced;
  // Keep the case, but make look-alike letters the same in both cases.
  final out = StringBuffer();
  for (final ch in spaced.split('')) {
    final low = ch.toLowerCase();
    final same = looseText(low);
    out.write(ch == low ? same : same.toUpperCase());
  }
  return out.toString();
}

/// Fewest letter changes (replace, insert, delete) that turn [pattern] into
/// [text] — or, with [part], into the best-matching piece of [text].
int textDistance(String text, String pattern, {bool part = false}) {
  final n = pattern.length, m = text.length;
  if (n == 0) return 0;
  if (m == 0) return n;
  var prev = List<int>.generate(m + 1, (j) => part ? 0 : j);
  for (var i = 1; i <= n; i++) {
    final cur = List<int>.filled(m + 1, i);
    for (var j = 1; j <= m; j++) {
      final cost = pattern.codeUnitAt(i - 1) == text.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return part ? prev.reduce(math.min) : prev[m];
}

/// How much [text] looks like [pattern], 0..100 (100 — the same).
int textSimilarity(String text, String pattern, [MatchRules rules = const MatchRules()]) {
  final t = _prepare(text, rules), p = _prepare(pattern, rules);
  if (p.isEmpty) return t.isEmpty || rules.part ? 100 : 0;
  final d = textDistance(t, p, part: rules.part);
  final base = rules.part ? p.length : math.max(p.length, t.length);
  return (100 * (1 - d / base)).clamp(0, 100).round();
}

/// [text] matches [pattern] within the allowed mistakes.
bool textMatches(String text, String pattern, [MatchRules rules = const MatchRules()]) {
  final t = _prepare(text, rules), p = _prepare(pattern, rules);
  if (p.isEmpty) return true;
  final percent = rules.percent;
  if (percent != null) return textSimilarity(text, pattern, rules) >= percent;
  final allowed = rules.errors ?? autoErrors(p.length);
  return textDistance(t, p, part: rules.part) <= allowed;
}
