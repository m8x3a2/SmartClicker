// Past versions of scripts (the data folder `versions\`): before a script file
// is overwritten with other text, the old text is put aside; the last [keep]
// versions of every script stay. Shown by «Прошлые версии…».

import 'dart:io';
import 'dart:math' as math;

/// One kept text of a script; [time] — when that text was saved.
class ScriptVersion {
  final String path;
  final DateTime time;
  const ScriptVersion(this.path, this.time);

  String read() {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  int get size {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }
}

/// Versions lie in `versions\Папка\Имя.cks\2026-11-16 20-11-05.cks`: the
/// folder of a script ends with .cks, and names of scripts and folders never
/// do, so a script and a folder of the same name do not mix.
class ScriptVersions {
  final String dir;

  /// How many versions of a script to keep; 0 — keep none.
  int keep;
  ScriptVersions(this.dir, {this.keep = 20});

  static final _sep = Platform.pathSeparator;
  static final _stampRe = RegExp(r'^(\d{4})-(\d\d)-(\d\d) (\d\d)-(\d\d)-(\d\d)');

  String _folder(String name) => '$dir$_sep${name.replaceAll('/', _sep)}.cks';

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  }

  /// "2026-11-16 20-11-05 (3).cks" → 3; without a number — 1.
  static int _number(String file) =>
      int.tryParse(RegExp(r'\((\d+)\)\.cks$').firstMatch(file)?.group(1) ?? '') ?? 1;

  static DateTime? _parse(String file) {
    final m = _stampRe.firstMatch(file);
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  /// Versions of [name], newest first.
  List<ScriptVersion> of(String name) {
    final d = Directory(_folder(name));
    if (!d.existsSync()) return [];
    final out = <(String, ScriptVersion)>[];
    for (final f in d.listSync().whereType<File>()) {
      final file = f.path.substring(f.path.lastIndexOf(_sep) + 1);
      if (!file.toLowerCase().endsWith('.cks')) continue;
      final t = _parse(file);
      if (t != null) out.add((file, ScriptVersion(f.path, t)));
    }
    // "… (2)" is newer than the same second without a number
    out.sort((a, b) {
      final c = b.$2.time.compareTo(a.$2.time);
      return c != 0 ? c : _number(b.$1).compareTo(_number(a.$1));
    });
    return [for (final v in out) v.$2];
  }

  /// Puts aside [text] of [name], saved at [savedAt]. An empty text (a new
  /// script) and a text equal to the last kept one are not kept again.
  void put(String name, String text, DateTime savedAt) {
    if (keep <= 0 || text.trim().isEmpty) return;
    final list = of(name);
    if (list.isNotEmpty && list.first.read() == text) return;
    final d = Directory(_folder(name))..createSync(recursive: true);
    final base = _stamp(savedAt);
    // the same second: the next number after the largest one (a number freed
    // by pruning must not make the new version look the oldest)
    var last = 0;
    for (final f in d.listSync().whereType<File>()) {
      final file = f.path.substring(f.path.lastIndexOf(_sep) + 1);
      if (file.startsWith(base)) last = math.max(last, _number(file));
    }
    File(last == 0 ? '${d.path}$_sep$base.cks' : '${d.path}$_sep$base (${last + 1}).cks')
        .writeAsStringSync(text);
    _prune(name);
  }

  void _prune(String name) {
    for (final v in of(name).skip(keep)) {
      try {
        File(v.path).deleteSync();
      } catch (_) {}
    }
  }

  /// Fewer versions to keep: drops the extra ones of every script.
  void pruneAll() {
    for (final name in scripts()) {
      if (keep <= 0) {
        clear(name);
      } else {
        _prune(name);
      }
    }
  }

  /// Names of scripts that have versions.
  List<String> scripts() {
    final d = Directory(dir);
    if (!d.existsSync()) return [];
    return [
      for (final f in d.listSync(recursive: true).whereType<Directory>())
        if (f.path.toLowerCase().endsWith('.cks'))
          f.path.substring(dir.length + 1, f.path.length - 4).replaceAll(_sep, '/'),
    ];
  }

  /// The script was renamed or moved: its versions go along (with versions
  /// of a script that had the new name before, if any).
  void rename(String from, String to) {
    final src = Directory(_folder(from));
    if (!src.existsSync() || from == to) return;
    final dst = Directory(_folder(to));
    if (!dst.existsSync()) {
      dst.parent.createSync(recursive: true);
      src.renameSync(dst.path);
    } else {
      for (final f in src.listSync().whereType<File>()) {
        final file = f.path.substring(f.path.lastIndexOf(_sep) + 1);
        var target = File('${dst.path}$_sep$file');
        for (var i = 2; target.existsSync(); i++) {
          target = File('${dst.path}$_sep${file.substring(0, file.length - 4)} ($i).cks');
        }
        f.renameSync(target.path);
      }
      src.deleteSync(recursive: true);
      _prune(to);
    }
    _dropEmpty(src.parent);
  }

  /// Forgets every version of [name].
  void clear(String name) {
    final d = Directory(_folder(name));
    if (d.existsSync()) d.deleteSync(recursive: true);
    _dropEmpty(d.parent);
  }

  /// Removes folders left empty, up to the versions folder itself.
  void _dropEmpty(Directory d) {
    var cur = d;
    while (cur.path.length > dir.length && cur.existsSync() && cur.listSync().isEmpty) {
      cur.deleteSync();
      cur = cur.parent;
    }
  }
}
