// Text of the editor with ClickScript colours and search matches; where the
// caret is (code, string, comment).
part of 'code_editor.dart';

/// Text controller with simple syntax highlighting for ClickScript and
/// highlighting of search matches.
class CodeController extends TextEditingController {
  static final _re = RegExp(
    r'(//[^\n]*|/\*[\s\S]*?\*/)'
    r'''|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)'''
    r'|(#[0-9A-Fa-f]{6}\b)'
    r'|(\b\d+(?:\.\d+)?(?:ms|s|m|h|px)?%?)'
    r'|\b(let|var|const|if|else|while|for|in|of|repeat|break|continue|return|function|true|false|null|switch|case|default|try|catch|finally|throw|do)\b'
    r'|(\b[A-Za-z_]\w*(?=\s*\())',
  );

  static const _comment = TextStyle(color: Color(0xFF6B7385), fontStyle: FontStyle.italic);
  static const _string = TextStyle(color: Color(0xFF9CCB7A));
  static const _number = TextStyle(color: Color(0xFFE0A66A));
  static const _keyword = TextStyle(color: Color(0xFFC792EA));
  static const _call = TextStyle(color: Color(0xFF6CB6FF));
  static const _matchColor = Color(0x664F6A2A);
  static const _activeMatchColor = Color(0xFFB8860B);

  // ---- search
  String _query = '';
  int _active = -1;
  String _matchText = '';
  String _matchQuery = '';
  List<TextRange> _matches = const [];

  String get query => _query;
  set query(String q) {
    if (q == _query) return;
    _query = q;
    notifyListeners();
  }

  /// Index of the match the search is standing on (-1 = none).
  int get activeMatch => _active;
  set activeMatch(int i) {
    if (i == _active) return;
    _active = i;
    notifyListeners();
  }

  /// Places where [query] occurs in the text (case is ignored).
  List<TextRange> get matches {
    if (_matchQuery != _query || _matchText != text) {
      _matchQuery = _query;
      _matchText = text;
      _matches = _query.isEmpty
          ? const []
          : [
              for (final m in RegExp(RegExp.escape(_query), caseSensitive: false)
                  .allMatches(text))
                TextRange(start: m.start, end: m.end),
            ];
    }
    return _matches;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context, TextStyle? style, required bool withComposing}) {
    final src = text;
    final found = matches;
    final spans = <TextSpan>[];
    var mi = 0;

    // Adds src[from..to) in one style, cutting out the search matches.
    void add(int from, int to, TextStyle? st) {
      var pos = from;
      while (pos < to) {
        while (mi < found.length && found[mi].end <= pos) {
          mi++;
        }
        if (mi < found.length && found[mi].start < to) {
          final m = found[mi];
          if (m.start > pos) {
            spans.add(TextSpan(text: src.substring(pos, m.start), style: st));
            pos = m.start;
          }
          final end = math.min(m.end, to);
          spans.add(TextSpan(
            text: src.substring(pos, end),
            style: (st ?? const TextStyle()).copyWith(
              backgroundColor: mi == _active ? _activeMatchColor : _matchColor,
              color: mi == _active ? Colors.white : null,
            ),
          ));
          pos = end;
        } else {
          spans.add(TextSpan(text: src.substring(pos, to), style: st));
          pos = to;
        }
      }
    }

    var pos = 0;
    for (final m in _re.allMatches(src)) {
      if (m.start > pos) add(pos, m.start, null);
      final TextStyle s;
      if (m.group(1) != null) {
        s = _comment;
      } else if (m.group(2) != null || m.group(3) != null) {
        s = _string;
      } else if (m.group(4) != null) {
        s = _number;
      } else if (m.group(5) != null) {
        s = _keyword;
      } else {
        s = _call;
      }
      add(m.start, m.end, s);
      pos = m.end;
    }
    if (pos < src.length) add(pos, src.length, null);
    return TextSpan(style: style, children: spans);
  }
}

/// What the part of a line before the caret is inside of.
enum _Inside { code, string, comment }

_Inside _lineContext(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'" || ch == '`') {
      quote = ch;
    } else if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return _Inside.comment;
    }
  }
  return quote == null ? _Inside.code : _Inside.string;
}
