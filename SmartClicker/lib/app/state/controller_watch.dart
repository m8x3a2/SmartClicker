// Scripts changed by other programs (a neural network, an editor): new and
// deleted files appear in the list, the open script shows the new text, or —
// with unsaved edits — the user chooses (see ExternalChangeBanner).
part of 'app_controller.dart';

extension AppControllerWatch on AppController {
  /// Called from the poll every 2 seconds.
  void _checkDiskChanges() {
    try {
      final list = store.list();
      final folders = store.folders();
      if (!_sameList(list, scripts) || !_sameList(folders, this.folders)) {
        scripts = list;
        this.folders = folders;
        _changed();
      }
      final name = current;
      if (name == null || !store.exists(name)) return;
      final disk = store.read(name);
      if (disk == _savedText || disk == externalText) return;
      // the text before the other program's edit: not lost (Прошлые версии)
      store.versions?.put(name, _savedText, DateTime.now());
      if (!dirty) {
        _savedText = disk;
        _setEditor(disk);
        dirty = false;
        notify('Скрипт обновлён', '«$name» изменён другой программой — показан новый текст');
        _log('system', '↻ «$name» изменён на диске другой программой — текст обновлён');
        _changed();
      } else {
        // Unsaved edits here and a new text on disk: the user decides.
        externalText = disk;
        _changed();
      }
    } catch (e, s) {
      ErrorJournal.record(e, s, where: 'disk watch');
    }
  }

  /// "Take from disk": the text from disk replaces the unsaved edits (they
  /// stay in Ctrl+Z).
  void takeExternal() {
    final disk = externalText;
    if (disk == null || current == null) return;
    externalText = null;
    _savedText = disk;
    _setEditor(disk);
    dirty = false;
    _changed();
  }

  /// "Keep mine": the unsaved edits stay; Ctrl+S writes them over the disk.
  void keepMine() {
    final disk = externalText;
    if (disk == null) return;
    externalText = null;
    _savedText = disk;
    dirty = editor.text != _savedText;
    _changed();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A file the open script reads or writes (the "Файлы" tab under the editor).
class LinkedFile {
  /// As written in the script, or a description ("data.json — save_data").
  final String label;
  final String path;

  /// What the script does with it: "читает, пишет".
  final String uses;

  /// First line that mentions it (0 — the program itself writes it).
  final int line;
  const LinkedFile(this.label, this.path, this.uses, this.line);
}

extension AppControllerLinkedFiles on AppController {
  /// Files of the open script (by its text in the editor), plus state.json
  /// when the program writes it and data.json when save_data is used.
  List<LinkedFile> linkedFiles() {
    final refs = findFileRefs(editor.text);
    final sep = Platform.pathSeparator;
    String full(String name) {
      final abs = name.startsWith('/') ||
          name.startsWith(r'\') ||
          RegExp(r'^[A-Za-z]:').hasMatch(name);
      return abs ? name : '${paths.files}$sep$name';
    }

    final out = [
      for (final r in refs.files) LinkedFile(r.name, full(r.name), r.uses.join(', '), r.line),
    ];
    final state = full('state.json');
    if (settings.stateFile && !out.any((f) => f.path.toLowerCase() == state.toLowerCase())) {
      out.add(LinkedFile('state.json', state, 'программа пишет состояние скрипта', 0));
    }
    if (refs.data) {
      out.add(LinkedFile('data.json', paths.dataFile, 'save_data / load_data — общие значения', 0));
    }
    return out;
  }

  /// Saves a file edited on the "Файлы" tab (written whole, never half).
  String? saveLinkedFile(String path, String text) {
    try {
      final tmp = File('$path.tmp')..parent.createSync(recursive: true);
      tmp.writeAsStringSync(text);
      tmp.renameSync(path);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}

extension AppControllerOldText on AppController {
  /// Past versions of [script], newest first (see ScriptVersions).
  List<ScriptVersion> versionsOf(String script) => store.versions?.of(script) ?? [];

  void clearVersions(String script) => store.versions?.clear(script);

  /// The text of [script] as the user sees it now (with unsaved edits).
  String textOf(String script) =>
      script == current ? editor.text : (buffers[script] ?? store.read(script));

  /// The text of [script] from the history of runs goes into the editor as
  /// unsaved edits: Ctrl+S keeps it, Ctrl+Z gives back the current one.
  void loadOldText(String script, String text) {
    if (!store.exists(script)) {
      notify('Скрипта нет', '«$script» удалён или переименован', level: 'warn');
      return;
    }
    if (isRunning) {
      notify('Скрипт работает', 'Сначала остановите его', level: 'warn');
      return;
    }
    open(script);
    _setEditor(text);
    dirty = editor.text != _savedText;
    openPage('scripts');
    notify('Старый текст в редакторе',
        'Сохраните (Ctrl+S), чтобы оставить его; Ctrl+Z вернёт нынешний', level: 'ok');
    _changed();
  }
}
