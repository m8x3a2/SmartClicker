// Where a script mentions a picture of the "files" folder, and renaming that
// picture in the script text. Used by the "Pictures" page, the checker and
// the editor (the names of picture functions are kept here, in one place).

import 'lexer.dart';

/// Functions whose first argument is a picture that must exist.
const pictureReaders = {
  'click_image', 'find_image', 'wait_image', //
  'clickImage', 'findImage', 'waitImage',
};

/// All functions whose first argument is the name of a picture
/// (`screenshot` makes one).
const pictureFunctions = {...pictureReaders, 'screenshot'};

/// One mention of a picture in a script.
class PictureRef {
  /// 1-based line and the text of that line (for the list shown to the user).
  final int line;
  final String lineText;

  /// Offsets of the quoted name in the source: [start, end), quotes included.
  final int start, end;

  /// The first argument of a picture function; otherwise just a string with
  /// the same name (e.g. `let pic = "кнопка"` used later).
  final bool direct;
  const PictureRef(this.line, this.lineText, this.start, this.end, {required this.direct});
}

/// "кнопка", "Кнопка.png" and "кнопка.PNG" are the same file on Windows.
bool samePictureName(String literal, String name) {
  String n(String s) {
    final t = s.trim().toLowerCase();
    return t.endsWith('.png') ? t.substring(0, t.length - 4) : t;
  }

  return n(literal) == n(name) && n(name).isNotEmpty;
}

/// Mentions of picture [name] in [source], in order.
List<PictureRef> findPictureRefs(String source, String name) {
  final List<Token> tokens;
  try {
    tokens = Lexer(source).scan();
  } catch (_) {
    return _findByPattern(source, name); // a script that does not parse
  }
  final lines = source.split('\n');
  final refs = <PictureRef>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.type != T.string || t.value is! String) continue;
    final q = source.substring(t.start, t.start + 1);
    if (q != '"' && q != "'") continue; // not a quoted string (e.g. a colour)
    if (!samePictureName(t.value as String, name)) continue;
    final direct = i >= 2 &&
        tokens[i - 1].isOp('(') &&
        tokens[i - 2].type == T.ident &&
        pictureFunctions.contains(tokens[i - 2].text);
    refs.add(PictureRef(t.line, lines[t.line - 1].trim(), t.start, t.end, direct: direct));
  }
  return refs;
}

List<PictureRef> _findByPattern(String source, String name) {
  final refs = <PictureRef>[];
  final re = RegExp(r'''([A-Za-z_]\w*)\s*\(\s*(["'])([^"'\\\n]*)\2''');
  final lines = source.split('\n');
  var offset = 0;
  for (var l = 0; l < lines.length; l++) {
    for (final m in re.allMatches(lines[l])) {
      if (!pictureFunctions.contains(m[1]) || !samePictureName(m[3]!, name)) continue;
      final end = m.end;
      final start = end - m[3]!.length - 2;
      refs.add(PictureRef(l + 1, lines[l].trim(), offset + start, offset + end, direct: true));
    }
    offset += lines[l].length + 1;
  }
  return refs;
}

/// [source] with the mentions [refs] renamed to [newName]. The quote style
/// and a written ".png" stay as they were.
String renamePictureRefs(String source, List<PictureRef> refs, String newName) {
  final sorted = [...refs]..sort((a, b) => b.start.compareTo(a.start));
  var out = source;
  for (final r in sorted) {
    final old = out.substring(r.start, r.end);
    final quote = old[0];
    final hadPng = old.toLowerCase().endsWith('.png$quote');
    out = out.replaceRange(r.start, r.end, '$quote$newName${hadPng ? '.png' : ''}$quote');
  }
  return out;
}
