// "Share a script": one ZIP with the script, the pictures it uses and the
// scripts it runs; reading such a ZIP (or an export of all scripts) back,
// with the commands inside that can do harm on this computer.

import 'dart:convert';
import 'dart:typed_data';

import '../lang/ast.dart';
import '../lang/lexer.dart';
import '../lang/parser.dart';
import '../lang/picture_refs.dart';
import '../lang/script_refs.dart';
import 'script_store.dart';
import 'zip.dart';

/// Description of a shared archive: which script is the main one.
const shareManifestName = 'smartclicker-share.json';

String _pictureName(String s) {
  final t = s.trim();
  return t.toLowerCase().endsWith('.png') ? t.substring(0, t.length - 4) : t;
}

/// A picture name that may go into an archive: relative, no "..".
bool _safePicture(String name) =>
    name.isNotEmpty &&
    !name.contains(':') &&
    !name.startsWith('/') &&
    !name.startsWith(r'\') &&
    ScriptStore.sanitize(name) == name.replaceAll(r'\', '/');

/// What goes into the archive of a script.
class SharePlan {
  final String main;

  /// The main script first, then the scripts it runs (at any depth).
  final List<String> scripts;

  /// Pictures of the files folder mentioned in those scripts.
  final List<String> pictures;

  /// Pictures the scripts look for that are not in the files folder.
  final List<String> missing;
  const SharePlan(this.main, this.scripts, this.pictures, this.missing);
}

/// Collects [main], the scripts it runs with run_script and every picture
/// they mention. [scripts] — all scripts (name → text).
SharePlan planShare(String main, Map<String, String> scripts,
    {required bool Function(String picture) pictureExists,
    Set<String> pictureReaders = const {}}) {
  final order = <String>[];
  final pictures = <String>[];
  final missing = <String>[];
  final seenPic = <String>{};
  void visit(String name) {
    if (order.contains(name)) return;
    final text = scripts[name];
    if (text == null) return;
    order.add(name);
    List<Token> tokens;
    try {
      tokens = Lexer(text).scan();
    } catch (_) {
      tokens = const [];
    }
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type != T.string || t.value is! String) continue;
      final pic = _pictureName(t.value as String);
      if (!_safePicture(pic) || !seenPic.add(pic.toLowerCase())) continue;
      if (pictureExists(pic)) {
        pictures.add(pic);
      } else if (i >= 2 &&
          tokens[i - 1].isOp('(') &&
          tokens[i - 2].type == T.ident &&
          pictureReaders.contains(tokens[i - 2].text)) {
        missing.add(pic);
      }
    }
    for (final r in findScriptRefs(text)) {
      final other = resolveScriptName(r.name, scripts.keys);
      if (other != null) visit(other);
    }
  }

  visit(main);
  return SharePlan(main, order, pictures, missing);
}

/// The ZIP of [plan]: scripts/…cks, files/…png and the description.
Uint8List encodeShare(SharePlan plan, Map<String, String> scripts,
    List<int>? Function(String picture) readPicture) {
  final files = <String, List<int>>{
    shareManifestName: utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'format': 1,
      'main': plan.main,
      'scripts': plan.scripts,
      'pictures': plan.pictures,
    })),
    for (final s in plan.scripts) 'scripts/$s${ScriptStore.ext}': utf8.encode(scripts[s]!),
  };
  for (final p in plan.pictures) {
    final bytes = readPicture(p);
    if (bytes != null) files['files/$p.png'] = bytes;
  }
  return zipEncode(files);
}

/// Contents of an archive being imported.
class ShareArchive {
  /// The main script of a shared archive; null for an export of all scripts.
  final String? main;
  final Map<String, String> scripts;
  final Map<String, Uint8List> pictures;
  const ShareArchive(this.main, this.scripts, this.pictures);
}

/// Reads a shared archive or an export of all scripts (.cks files at any
/// place, no pictures).
ShareArchive readShare(Uint8List bytes) {
  final files = zipDecode(bytes);
  final scripts = <String, String>{};
  final pictures = <String, Uint8List>{};
  String? main;
  final manifest = files[shareManifestName];
  if (manifest != null) {
    try {
      final j = jsonDecode(utf8.decode(manifest));
      if (j is Map && j['main'] is String) main = ScriptStore.sanitize(j['main'] as String);
    } catch (_) {}
  }
  final shared = manifest != null;
  files.forEach((path, data) {
    final p = path.replaceAll(r'\', '/');
    final lower = p.toLowerCase();
    if (lower.endsWith(ScriptStore.ext)) {
      final rel = shared && lower.startsWith('scripts/') ? p.substring(8) : p;
      if (shared && !lower.startsWith('scripts/')) return;
      final name = ScriptStore.sanitize(rel);
      if (name.isNotEmpty) scripts[name] = utf8.decode(data, allowMalformed: true);
    } else if (shared && lower.startsWith('files/') && lower.endsWith('.png')) {
      final name = ScriptStore.sanitize(_pictureName(p.substring(6)));
      if (name.isNotEmpty) pictures[name] = data;
    }
  });
  if (main != null && !scripts.containsKey(main)) main = null;
  return ShareArchive(main, scripts, pictures);
}

/// A command of a script that can do harm on this computer.
class Danger {
  final String script;
  final int line;
  final String command;

  /// The line of code, trimmed.
  final String code;
  const Danger(this.script, this.line, this.command, this.code);

  String get what => dangerousCommands[command]!;
}

/// Commands worth a warning before a foreign script is added.
const dangerousCommands = {
  'run_command': 'выполняет любую команду Windows',
  'system_power': 'может выключить, перезагрузить или усыпить компьютер',
  'kill_process': 'закрывает программы',
  'write_file': 'записывает файлы на диск',
  'append_file': 'дописывает в файлы на диске',
  'launch': 'запускает программы, файлы или ссылки',
};

/// Dangerous commands in [source] of script [script], in order.
List<Danger> findDangers(String script, String source) {
  final List<Stmt> program;
  try {
    program = parseProgram(source);
  } catch (_) {
    // Not parsed: look for the names in the text.
    final lines = source.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        for (final c in dangerousCommands.keys)
          if (RegExp('\\b($c|${_camel(c)})\\s*\\(').hasMatch(lines[i]))
            Danger(script, i + 1, c, lines[i].trim()),
    ];
  }
  final lines = source.split('\n');
  final found = <Danger>[];
  for (final s in program) {
    walkNode(s, (n) {
      if (n is! Call || n.callee is! Ident) return;
      final name = (n.callee as Ident).name;
      for (final c in dangerousCommands.keys) {
        if (name == c || name == _camel(c)) {
          final code = n.line - 1 < lines.length ? lines[n.line - 1].trim() : '';
          found.add(Danger(script, n.line, c, code));
        }
      }
    });
  }
  found.sort((a, b) => a.line.compareTo(b.line));
  return found;
}

String _camel(String snake) =>
    snake.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase());

// ------------------------------------------------------------------- import

/// add — new; rename — as «… (импорт)»; skip — keep mine; replace — the
/// archive's version over mine.
enum ImportAction { add, rename, skip, replace }

/// One script or picture of an archive being imported.
class ImportItem {
  final bool picture;
  final String name;

  /// Something with this name already exists here.
  final bool exists;

  /// …and it is exactly the same: nothing to add.
  final bool same;
  ImportAction action;
  ImportItem(this.picture, this.name, {required this.exists, required this.same})
      : action = !exists ? ImportAction.add : (same ? ImportAction.skip : ImportAction.rename);
}

/// What an import will do: the items and the dangerous commands.
class ImportPlan {
  final ShareArchive archive;
  final List<ImportItem> items;
  final List<Danger> dangers;

  /// Whether a script / picture with this name is here already.
  final bool Function(String script) scriptTaken;
  final bool Function(String picture) pictureTaken;

  /// The text of my script with this name (for «Различия»), or null.
  final String? Function(String script) mine;
  const ImportPlan(this.archive, this.items, this.dangers,
      {required this.scriptTaken, required this.pictureTaken, required this.mine});
}

ImportPlan planImport(ShareArchive a,
    {required String? Function(String script) existingScript,
    required Uint8List? Function(String picture) existingPicture}) {
  bool sameBytes(Uint8List x, Uint8List y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  final names = [
    if (a.main != null) a.main!,
    ...a.scripts.keys.where((n) => n != a.main),
  ];
  ImportItem script(String n) {
    final old = existingScript(n);
    return ImportItem(false, n,
        exists: old != null, same: old != null && old.trim() == a.scripts[n]!.trim());
  }

  ImportItem picture(String n) {
    final old = existingPicture(n);
    return ImportItem(true, n,
        exists: old != null, same: old != null && sameBytes(old, a.pictures[n]!));
  }

  final items = [...names.map(script), ...a.pictures.keys.map(picture)];
  final dangers = [for (final n in names) ...findDangers(n, a.scripts[n]!)];
  return ImportPlan(a, items, dangers,
      scriptTaken: (n) => existingScript(n) != null,
      pictureTaken: (n) => existingPicture(n) != null,
      mine: existingScript);
}

/// Free name for a renamed item: "имя (импорт)", "имя (импорт 2)"…
String importName(String name, bool Function(String) taken) {
  var n = 1;
  String candidate() => n == 1 ? '$name (импорт)' : '$name (импорт $n)';
  while (taken(candidate())) {
    n++;
  }
  return candidate();
}

/// The result of an import: what is written under which name.
class ImportResult {
  /// Final name → text (the run_script and picture names already fixed).
  final Map<String, String> scripts;

  /// Final name → bytes of the PNG.
  final Map<String, Uint8List> pictures;

  /// Name in the archive → final name of every script that is written.
  final Map<String, String> scriptNames;

  /// Scripts that are the same as here but are still added as a copy: they
  /// run a renamed script or use a renamed picture of the archive.
  final Set<String> copied;
  const ImportResult(this.scripts, this.pictures, this.scriptNames, this.copied);
}

/// What to write: renamed items get "(импорт)", the imported scripts are
/// fixed to use the new names. A script of the archive that is the same as
/// here but runs a renamed script (or uses a renamed picture) would run the
/// one already here — it is added as a copy too.
ImportResult resolveImport(ImportPlan plan) {
  final scriptNames = <String, String>{};
  final pictureNames = <String, String>{};
  String rename(String name, bool picture) {
    final map = picture ? pictureNames : scriptNames;
    final taken = picture ? plan.pictureTaken : plan.scriptTaken;
    return importName(name, (c) => taken(c) || map.containsValue(c));
  }

  for (final i in plan.items) {
    if (i.action == ImportAction.skip) continue;
    // add and replace keep the name (replace writes over mine).
    (i.picture ? pictureNames : scriptNames)[i.name] =
        i.action == ImportAction.rename ? rename(i.name, i.picture) : i.name;
  }
  Map<String, String> renamed(Map<String, String> m) => {
        for (final e in m.entries)
          if (e.key != e.value) e.key: e.value,
      };

  bool usesRenamed(String text) {
    final scripts = renamed(scriptNames).keys;
    final pictures = renamed(pictureNames).keys;
    return findScriptRefs(text).any((r) => resolveScriptName(r.name, scripts) != null) ||
        pictures.any((p) => findPictureRefs(text, p).isNotEmpty);
  }

  final copied = <String>{};
  for (var again = true; again;) {
    again = false;
    for (final i in plan.items) {
      if (i.picture || !i.same || scriptNames.containsKey(i.name)) continue;
      if (usesRenamed(plan.archive.scripts[i.name]!)) {
        scriptNames[i.name] = rename(i.name, false);
        copied.add(i.name);
        again = true;
      }
    }
  }
  final renamedScripts = renamed(scriptNames);
  final renamedPictures = renamed(pictureNames);
  final scripts = <String, String>{};
  for (final e in scriptNames.entries) {
    var text = plan.archive.scripts[e.key]!;
    renamedScripts.forEach((old, name) => text = renameScriptRefs(text, old, name));
    renamedPictures.forEach(
        (old, name) => text = renamePictureRefs(text, findPictureRefs(text, old), name));
    scripts[e.value] = text;
  }
  return ImportResult(
    scripts,
    {for (final e in pictureNames.entries) e.value: plan.archive.pictures[e.key]!},
    scriptNames,
    copied,
  );
}
