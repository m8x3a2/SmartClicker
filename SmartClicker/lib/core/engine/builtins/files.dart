// Built-in functions: JSON files shared with other programs (a neural
// network writes a task, the script reads it), waiting for a file to change,
// writing the variables of the script for others to read.
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsFiles on ScriptRuntime {
  void _registerFiles() {
    // read_json("задание.json") — the whole file; with a key — one value
    // ("a.b.0" goes inside); the third argument — when there is no value.
    _def('read_json', (c) {
      final path = _path(_s(c, c.arg(0), 'read_json'));
      final key = c.arg(1, 'key');
      final def = c.arg(2, 'default');
      final data = _readJsonFile(c, path, 'read_json');
      if (data == null) return def;
      if (key == null) return data;
      final v = _jsonAt(data, _s(c, key, 'read_json'));
      return v ?? def;
    });

    // write_json("задание.json", value) — the whole file;
    // write_json("задание.json", "done", true) — one key, the rest stays.
    _def('write_json', (c) {
      final path = _path(_s(c, c.arg(0), 'write_json'));
      _guardWrite(c, 'write_json', path);
      Object? out;
      if (c.args.length >= 3) {
        final old = _readJsonFile(c, path, 'write_json');
        final root = old is Map ? Map<String, Object?>.from(old) : <String, Object?>{};
        _jsonPut(c, root, _s(c, c.arg(1), 'write_json'), _jsonSafe(c.arg(2)));
        out = root;
      } else {
        out = _jsonSafe(c.arg(1));
      }
      _writeAtomic(path, const JsonEncoder.withIndent('  ').convert(out));
      return null;
    });

    // Waits until the file changes (or appears); with key: — until that
    // value becomes value: (or anything true, without value:).
    _def('wait_file', (c) => _explicit(() async {
      final path = _path(_s(c, c.arg(0), 'wait_file'));
      final key = c.opt('key');
      final hasValue = c.named.containsKey('value');
      final want = c.opt('value');
      final timeout = _nOr(c, c.opt('timeout'), 0, 'timeout');
      final interval = math.max(_nOr(c, c.opt('interval'), 1000, 'interval'), 50);
      final start = _stamp(path);
      final sw = Stopwatch()..start();
      while (true) {
        if (key == null) {
          if (_stamp(path) != start) return true;
        } else {
          final data = _readJsonFile(c, path, 'wait_file', quiet: true);
          final v = data == null ? null : _jsonAt(data, _s(c, key, 'wait_file'));
          if (hasValue ? _sameJson(v, want) : truthy(v)) return true;
        }
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return false;
        await this.sleep(interval, jitter: false);
      }
    }));

    // export_vars("состояние.json") — the variables of the script right now,
    // for another program (a neural network) to see where the script is.
    _def('export_vars', (c) {
      final path = _path(c.args.isEmpty ? 'state.json' : _s(c, c.arg(0), 'export_vars'));
      _guardWrite(c, 'export_vars', path);
      _writeAtomic(
          path,
          const JsonEncoder.withIndent('  ').convert({
            'script': cfg['main'],
            'line': c.line,
            'updated': DateTime.now().toIso8601String(),
            'vars': variableValues(),
          }));
      return null;
    });
  }

  /// Values of the variables seen from the current place (JSON-safe).
  Map<String, Object?> variableValues() {
    final out = <String, Object?>{};
    final g = interp.globals;
    for (Env? e = interp.currentEnv; e != null; e = e.parent) {
      final global = identical(e, g);
      for (final en in e.vars.entries) {
        final v = en.value;
        if (v is UserFn || v is Builtin) continue;
        if (global && _engineNames.contains(en.key)) continue;
        out.putIfAbsent(en.key, () => _jsonSafe(v));
      }
    }
    return out;
  }

  /// Contents of a JSON file: null when there is none (or it is being
  /// written — [quiet]); broken JSON is an error of the script.
  Object? _readJsonFile(CallCtx c, String path, String fn, {bool quiet = false}) {
    final f = File(path);
    if (!f.existsSync()) return null;
    String text;
    try {
      text = f.readAsStringSync();
    } catch (e) {
      if (quiet) return null;
      c.fail('$fn: не удалось прочитать "$path": $e');
    }
    if (text.startsWith('﻿')) text = text.substring(1); // Notepad's BOM
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      if (quiet) return null; // another program is writing it right now
      c.fail('$fn: в "$path" не JSON: ${e.message}');
    }
  }

  /// The value at "a.b.0" inside [data], or null.
  Object? _jsonAt(Object? data, String key) {
    Object? v = data;
    for (final part in key.split('.')) {
      if (v is Map) {
        v = v[part];
      } else if (v is List) {
        final i = int.tryParse(part);
        if (i == null || i < 0 || i >= v.length) return null;
        v = v[i];
      } else {
        return null;
      }
    }
    return v;
  }

  void _jsonPut(CallCtx c, Map<String, Object?> root, String key, Object? value) {
    final parts = key.split('.');
    var m = root;
    for (final p in parts.take(parts.length - 1)) {
      final next = m[p];
      if (next is Map) {
        m = m[p] = Map<String, Object?>.from(next);
      } else {
        m = m[p] = <String, Object?>{};
      }
    }
    m[parts.last] = value;
  }

  bool _sameJson(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    return jsonEncode(_jsonSafe(a)) == jsonEncode(_jsonSafe(b));
  }

  /// When and how big the file is ('' — none): a change of either is a change.
  String _stamp(String path) {
    try {
      final s = File(path).statSync();
      if (s.type == FileSystemEntityType.notFound) return '';
      return '${s.modified.microsecondsSinceEpoch}:${s.size}';
    } catch (_) {
      return '';
    }
  }

  /// Written to a temporary file first and then renamed: a reader never
  /// sees half a file.
  void _writeAtomic(String path, String text) {
    final tmp = File('$path.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(text);
    tmp.renameSync(path);
  }
}
