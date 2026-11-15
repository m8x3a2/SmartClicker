// Search in all scripts (Ctrl+Shift+F): where a word, command or picture is
// used — script, line, the line itself and where the match is in it.

/// One match.
class SearchHit {
  final String script;

  /// 1-based line and its text; [start] — where the match begins in it.
  final int line;
  final String text;
  final int start, length;
  const SearchHit(this.script, this.line, this.text, this.start, this.length);
}

/// Not more matches than this (a search for "a" in 100 scripts).
const searchLimit = 500;

/// Matches of [query] in [scripts] (name → text), scripts in name order.
/// [wholeWord] — "click" does not match "click_image".
List<SearchHit> searchScripts(Map<String, String> scripts, String query,
    {bool caseSensitive = false, bool wholeWord = false}) {
  if (query.isEmpty) return const [];
  final pattern = RegExp(
    wholeWord ? r'(?<![\p{L}\p{N}_])' + RegExp.escape(query) + r'(?![\p{L}\p{N}_])' : RegExp.escape(query),
    caseSensitive: caseSensitive,
    unicode: true,
  );
  final hits = <SearchHit>[];
  final names = scripts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  for (final name in names) {
    final lines = scripts[name]!.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].replaceAll('\r', '');
      for (final m in pattern.allMatches(text)) {
        hits.add(SearchHit(name, i + 1, text, m.start, m.end - m.start));
        if (hits.length >= searchLimit) return hits;
      }
    }
  }
  return hits;
}
