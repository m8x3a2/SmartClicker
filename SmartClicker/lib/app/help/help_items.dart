// Items of a help text that can be copied with one click: a point of a list
// with its wrapped lines, an example of code (without its indent, ready to
// paste), a line of the reference with its explanation.

class HelpItem {
  /// First line of the item (0-based) and how many lines it takes.
  final int line, lines;

  /// What goes to the clipboard.
  final String text;

  /// An example of code (copied as is, line by line).
  final bool code;
  const HelpItem(this.line, this.lines, this.text, {this.code = false});

  @override
  String toString() => '$line+$lines ${code ? 'code' : 'text'}: $text';
}

final _cyr = RegExp('[А-Яа-яЁё]');
final _bullet = RegExp(r'^(•|-|\*|\d+[.)])\s+');
final _separator = RegExp(r'^\s*([-=─_]{3,})\s*$');

/// A line of the reference: begins with a command ("find_image(", "Math.floor(").
final _entry = RegExp(r'^[A-Za-z_][\w.]*\s*\(');

int _indent(String l) => l.length - l.trimLeft().length;

/// A line of code: without the texts in quotes and the comment, no Russian
/// letters are left (a sentence always has them).
bool isCodeLine(String line) {
  final t = line.trim();
  if (t.isEmpty || _bullet.hasMatch(t)) return false;
  var s = t.replaceAll(RegExp(r'"[^"]*"'), '""').replaceAll(RegExp(r"'[^']*'"), "''");
  final c = s.indexOf('//');
  if (c >= 0) s = s.substring(0, c);
  if (s.trim().isEmpty) return t.startsWith('//'); // a comment line of an example
  return !_cyr.hasMatch(s);
}

/// A heading: in capitals, or underlined by the next line (--- / ===).
bool _heading(List<String> lines, int i) {
  final t = lines[i].trim();
  if (_separator.hasMatch(lines[i])) return true;
  if (i + 1 < lines.length && _separator.hasMatch(lines[i + 1])) return true;
  return t.length >= 3 && t == t.toUpperCase() && _cyr.hasMatch(t) && !t.contains('(');
}

List<HelpItem> helpItems(String text) {
  final lines = text.split('\n');
  final out = <HelpItem>[];
  var i = 0;
  while (i < lines.length) {
    final l = lines[i];
    if (l.trim().isEmpty || _heading(lines, i)) {
      i++;
      continue;
    }
    if (isCodeLine(l)) {
      // an example: the lines of code that go one after another
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty && isCodeLine(lines[j])) {
        j++;
      }
      final block = lines.sublist(i, j);
      final cut = block.map(_indent).reduce((a, b) => a < b ? a : b);
      out.add(HelpItem(i, j - i, block.map((b) => b.substring(cut).trimRight()).join('\n'), code: true));
      i = j;
      continue;
    }
    // text: the line and its wrapped lines (indented deeper, not code); a
    // plain paragraph also goes on at the same indent — but a line of the
    // reference ("click(x, y)  …") always starts its own item
    final ind = _indent(l);
    final paragraph = !_bullet.hasMatch(l.trim()) && !_entry.hasMatch(l.trim());
    var j = i + 1;
    while (j < lines.length &&
        lines[j].trim().isNotEmpty &&
        (_indent(lines[j]) > ind || paragraph && _indent(lines[j]) == ind && !_entry.hasMatch(lines[j].trim())) &&
        !_heading(lines, j) &&
        !isCodeLine(lines[j]) &&
        !_bullet.hasMatch(lines[j].trim())) {
      j++;
    }
    final words = [
      l.trim().replaceFirst(_bullet, ''),
      for (var k = i + 1; k < j; k++) lines[k].trim(),
    ].join(' ');
    out.add(HelpItem(i, j - i, words));
    i = j;
  }
  return out;
}
