// Which scripts a script runs with run_script("name"): finding the script
// by the name written in the code, the mentions, renaming them.

import 'lexer.dart';

const _runScript = {'run_script', 'runScript'};

/// The script [ref] (as written in run_script) among [names]: the full
/// name first ("Папка/Имя"), then the last part only ("Имя"). Case and a
/// written ".cks" do not matter. Null if there is no such script.
String? resolveScriptName(String ref, Iterable<String> names) {
  final q = ref.toLowerCase().replaceAll(r'\', '/').replaceAll(RegExp(r'\.cks$'), '');
  for (final n in names) {
    if (n.toLowerCase() == q) return n;
  }
  for (final n in names) {
    if (n.toLowerCase().split('/').last == q) return n;
  }
  return null;
}

/// One run_script("…") in a script: offsets of the quoted name, quotes
/// included, and the name itself.
typedef ScriptRef = ({int start, int end, String name});

/// Every run_script("name") of [source] written with a plain quoted name.
List<ScriptRef> findScriptRefs(String source) {
  final List<Token> tokens;
  try {
    tokens = Lexer(source).scan();
  } catch (_) {
    return const [];
  }
  final refs = <ScriptRef>[];
  for (var i = 2; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.type != T.string || t.value is! String) continue;
    if (!tokens[i - 1].isOp('(') ||
        tokens[i - 2].type != T.ident ||
        !_runScript.contains(tokens[i - 2].text)) {
      continue;
    }
    refs.add((start: t.start, end: t.end, name: t.value as String));
  }
  return refs;
}

/// One run_script("…") to be changed after a rename: its line, the name
/// as written and the new one; [broken] — the old name would no longer
/// find the script (otherwise it still works, but by a short name).
typedef ScriptRefChange = ({int line, String from, String to, bool broken});

/// [source] after scripts were renamed or moved ([renames]: old → new name;
/// [before] and [after] — all script names before and after). Every
/// run_script of a renamed script gets its full new name ("Папка/Имя"), so
/// it can not later switch to another script of the same short name.
/// [only] picks which of the changes to make (all by default). Gives the
/// new text and the changes.
({String text, List<ScriptRefChange> changes}) fixScriptRefs(String source,
    Map<String, String> renames, List<String> before, List<String> after,
    {bool Function(ScriptRefChange change)? only}) {
  final refs = findScriptRefs(source)..sort((a, b) => b.start.compareTo(a.start));
  var out = source;
  final changes = <ScriptRefChange>[];
  for (final r in refs) {
    final was = resolveScriptName(r.name, before);
    final now = was == null ? null : renames[was];
    if (now == null || r.name == now) continue;
    final change = (
      line: '\n'.allMatches(source.substring(0, r.start)).length + 1,
      from: r.name,
      to: now,
      broken: resolveScriptName(r.name, after) != now,
    );
    if (only != null && !only(change)) continue;
    final quote = out[r.start];
    out = out.replaceRange(r.start, r.end, '$quote$now$quote');
    changes.add(change);
  }
  return (text: out, changes: changes.reversed.toList());
}

/// The scripts a short run_script name ("night 2", no folder) may mean
/// when several scripts have it; empty when the name is unambiguous.
List<String> ambiguousScriptName(String ref, Iterable<String> names) {
  final q = ref.toLowerCase().replaceAll(r'\', '/').replaceAll(RegExp(r'\.cks$'), '');
  if (q.contains('/')) return const [];
  final same = [for (final n in names) if (n.toLowerCase().split('/').last == q) n];
  return same.length > 1 ? same : const [];
}

/// [source] with run_script calls of the script [old] (any way of writing
/// its name that finds it) now naming [name]. The quote style stays.
String renameScriptRefs(String source, String old, String name) {
  final refs = findScriptRefs(source).where((r) => resolveScriptName(r.name, [old]) != null).toList()
    ..sort((a, b) => b.start.compareTo(a.start));
  var out = source;
  for (final r in refs) {
    final quote = out[r.start];
    out = out.replaceRange(r.start, r.end, '$quote$name$quote');
  }
  return out;
}
