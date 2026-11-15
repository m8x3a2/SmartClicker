// Files a script reads or writes (read_json("задание.json"), write_file(...)):
// shown on the "Файлы" tab under the editor. Found by the tokens of the
// lexer, like the pictures in picture_refs.dart.

import 'lexer.dart';

/// Functions whose first argument is a file, and what they do with it.
const fileFunctions = <String, String>{
  'read_json': 'читает',
  'write_json': 'пишет',
  'wait_file': 'ждёт',
  'export_vars': 'пишет',
  'read_file': 'читает',
  'write_file': 'пишет',
  'append_file': 'дописывает',
  'file_exists': 'проверяет',
};

/// One file mentioned by a script.
class FileRef {
  /// The name as written in the script ("задание.json", "C:\\x\\a.txt").
  final String name;

  /// First line where it is mentioned (1-based).
  final int line;

  /// What the script does with it: "читает, пишет".
  final List<String> uses;
  const FileRef(this.name, this.line, this.uses);
}

String _snake(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

/// Files in [source] (each once, in the order of the first mention), and
/// whether the script uses save_data / load_data (the shared data.json).
({List<FileRef> files, bool data}) findFileRefs(String source) {
  final List<Token> tokens;
  try {
    tokens = Lexer(source).scan();
  } catch (_) {
    return (files: const [], data: false); // a script that does not parse
  }
  final byName = <String, (String, int, List<String>)>{};
  var data = false;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.type != T.ident) continue;
    final fn = _snake(t.text);
    if (fn == 'save_data' || fn == 'load_data') data = true;
    final use = fileFunctions[fn];
    if (use == null) continue;
    // export_vars() without a name writes state.json.
    if (fn == 'export_vars' &&
        i + 2 < tokens.length &&
        tokens[i + 1].isOp('(') &&
        tokens[i + 2].isOp(')')) {
      _add(byName, 'state.json', t.line, use);
      continue;
    }
    if (i + 2 >= tokens.length || !tokens[i + 1].isOp('(')) continue;
    final arg = tokens[i + 2];
    if (arg.type != T.string || arg.value is! String) continue;
    final name = (arg.value as String).trim();
    if (name.isEmpty) continue;
    _add(byName, name, t.line, use);
  }
  return (
    files: [for (final e in byName.values) FileRef(e.$1, e.$2, e.$3)],
    data: data,
  );
}

void _add(Map<String, (String, int, List<String>)> byName, String name, int line, String use) {
  final key = name.toLowerCase().replaceAll('/', '\\');
  final old = byName[key];
  if (old == null) {
    byName[key] = (name, line, [use]);
  } else if (!old.$3.contains(use)) {
    old.$3.add(use);
  }
}

