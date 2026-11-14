// Scripts and folders of the open project: open, save, create, rename,
// move, copy, delete; inserting text into the editor.
part of 'app_controller.dart';

extension AppControllerScripts on AppController {
  void _refresh() {
    scripts = store.list();
    folders = store.folders();
  }

  /// Names of all scripts with unsaved changes.
  List<String> get unsaved =>
      [...buffers.keys, if (dirty && current != null) current!]..sort();

  bool isUnsaved(String name) =>
      buffers.containsKey(name) || (name == current && dirty);

  void _onEdit() {
    final count = '\n'.allMatches(editor.text).length + 1;
    final before = _lineCount;
    _lineCount = count;
    if (_loading || current == null) return;
    if (!_fromHistory) historyOf(current!).record(editor.value);
    if (count != before && breaks.value.isNotEmpty) _shiftBreaks(count - before);
    final d = editor.text != _savedText;
    if (d != dirty) {
      dirty = d;
      _changed();
    }
    if (errorLine.value != 0) errorLine.value = 0;
  }

  void _setEditor(String text) {
    editorEpoch++;
    _loading = true;
    editor.text = text;
    _loading = false;
    // A new text from outside (another script opened, «Сбросить», fixed
    // names) is a step too: it can be undone.
    if (current != null) historyOf(current!).record(editor.value);
  }

  /// The undo history of [script] (made on first use).
  EditHistory historyOf(String script) => _histories.putIfAbsent(script, EditHistory.new);

  /// Ctrl+Z in the code: the previous text of this script.
  void undoEdit() => _applyHistory(historyOf(current ?? '').undo());

  /// Ctrl+Y / Ctrl+Shift+Z.
  void redoEdit() => _applyHistory(historyOf(current ?? '').redo());

  void _applyHistory(TextEditingValue? v) {
    if (v == null || current == null || isRunning) return;
    _fromHistory = true;
    editor.value = v;
    _fromHistory = false;
  }

  /// Opens a script. Unsaved text of the previous one is kept in memory.
  void open(String name) {
    if (name == current) return;
    if (current != null && dirty) buffers[current!] = editor.text;
    current = name;
    selectedFolder = ScriptStore.folderOf(name);
    _savedText = store.read(name);
    _setEditor(buffers.remove(name) ?? _savedText);
    dirty = editor.text != _savedText;
    breaks.value = {...?settings.breakpoints[name]};
    errorLine.value = 0;
    currentLine.value = 0;
    _changed();
  }

  void save() {
    if (current == null || !dirty) return;
    store.write(current!, editor.text);
    _savedText = editor.text;
    dirty = false;
    _changed();
  }

  void saveAll() {
    save();
    buffers.forEach(store.write);
    buffers.clear();
    _changed();
  }

  /// Throws away unsaved changes of the open script.
  void revert() {
    if (current == null || !dirty) return;
    _loading = true;
    editor.text = _savedText;
    _loading = false;
    dirty = false;
    errorLine.value = 0;
    _changed();
  }

  /// Creates a script in [selectedFolder]. Returns an error message or null.
  String? create(String rawName, {String source = ''}) {
    final err = ScriptStore.validateName(rawName);
    if (err != null) return err;
    final clean = ScriptStore.sanitize(rawName);
    final name = selectedFolder.isEmpty ? clean : '$selectedFolder/$clean';
    if (store.exists(name)) return 'Скрипт с таким именем уже есть';
    store.write(name, source);
    _refresh();
    open(name);
    return null;
  }

  /// Moves everything that refers to script [old] over to [name].
  void _retarget(String old, String name) {
    final buf = buffers.remove(old);
    if (buf != null) buffers[name] = buf;
    final h = _histories.remove(old);
    if (h != null) _histories[name] = h;
    final key = settings.scriptKeys.remove(old);
    if (key != null) settings.scriptKeys[name] = key;
    for (final t in schedule.where((t) => t.script == old)) {
      t.script = name;
    }
    for (final r in autoRules.where((r) => r.script == old)) {
      r.script = name;
    }
    _retargetAnswers(old, name);
    if (current == old) {
      current = name;
      selectedFolder = ScriptStore.folderOf(name);
    }
  }

  /// After scripts were renamed or moved ([renames]: old → new; [before] —
  /// all names before), offers to fix run_script("…") of the renamed
  /// scripts in every script (window with check boxes, see
  /// [runScriptFixHandler]; without the interface — all of them): the full
  /// new name is written, on disk and in unsaved text (which stays unsaved).
  void _fixRunScripts(Map<String, String> renames, List<String> before) {
    final after = [for (final s in before) renames[s] ?? s];
    final fixes = <RunScriptFix>[];
    for (final s in after) {
      final text = _visibleText(s);
      final lines = text.split('\n');
      for (final c in fixScriptRefs(text, renames, before, after).changes) {
        fixes.add(RunScriptFix(s, c, lines[c.line - 1].trim()));
      }
    }
    if (fixes.isEmpty) return;
    final ask = runScriptFixHandler;
    if (ask == null) {
      _applyRunScriptFixes(fixes, renames, before, after);
      return;
    }
    ask(fixes).then((chosen) {
      if (chosen != null && chosen.isNotEmpty) {
        _applyRunScriptFixes(chosen, renames, before, after);
      }
    });
  }

  /// The text of [s] as the user sees it: the editor, an unsaved buffer or
  /// the file.
  String _visibleText(String s) => s == current ? editor.text : (buffers[s] ?? store.read(s));

  void _applyRunScriptFixes(List<RunScriptFix> chosen, Map<String, String> renames,
      List<String> before, List<String> after) {
    final changed = <String>[];
    for (final s in {for (final f in chosen) f.script}) {
      final mine = chosen.where((f) => f.script == s);
      final lines = {for (final f in mine) f.change.line};
      final names = {for (final f in mine) f.change.from};
      ({String text, List<ScriptRefChange> changes}) fix(String text, {bool byLine = true}) =>
          fixScriptRefs(text, renames, before, after,
              only: (c) => byLine ? lines.contains(c.line) : names.contains(c.from));
      final unsaved = s == current || buffers.containsKey(s);
      // The file of an unsaved script may differ in lines: the same names
      // are fixed there.
      final disk = fix(store.read(s), byLine: !unsaved);
      if (disk.changes.isNotEmpty) store.write(s, disk.text);
      if (s == current) {
        _savedText = disk.text;
        final text = fix(editor.text);
        if (text.changes.isNotEmpty) _setEditor(text.text);
        dirty = editor.text != _savedText;
      } else if (buffers[s] case final b?) {
        buffers[s] = fix(b).text;
      }
      changed.add('«$s» (стр. ${(lines.toList()..sort()).join(', ')})');
    }
    notify('run_script исправлен', 'Вызовы run_script обновлены: ${changed.join('; ')}',
        level: 'ok');
    _changed();
  }

  /// Renames or moves a script: "Имя" or "Папка/Имя".
  String? renameScript(String old, String rawName) {
    final err = ScriptStore.validateName(rawName);
    if (err != null) return err;
    final name = ScriptStore.sanitize(rawName);
    if (name == old) return null;
    if (store.exists(name)) return 'Скрипт с таким именем уже есть';
    final before = [...scripts];
    store.write(name, store.read(old));
    store.delete(old);
    _retarget(old, name);
    _fixRunScripts({old: name}, before);
    saveSettingsQuiet();
    saveSchedule();
    saveAutoRules();
    _refresh();
    _changed();
    return null;
  }

  String? rename(String rawName) =>
      current == null ? 'Нет открытого скрипта' : renameScript(current!, rawName);

  String? moveScript(String name, String folder) {
    final base = ScriptStore.baseOf(name);
    return renameScript(name, folder.isEmpty ? base : '$folder/$base');
  }

  /// Makes a copy next to the original and opens it.
  void duplicate(String name) {
    var n = 1;
    String candidate() => n == 1 ? '$name копия' : '$name копия $n';
    while (store.exists(candidate())) {
      n++;
    }
    final text = name == current ? editor.text : (buffers[name] ?? store.read(name));
    store.write(candidate(), text);
    _refresh();
    open(candidate());
  }

  void deleteScript(String name) {
    if (name == current) {
      deleteCurrent();
      return;
    }
    store.delete(name);
    buffers.remove(name);
    _forgetAnswers([name]);
    if (settings.scriptKeys.remove(name) != null) saveSettingsQuiet();
    _refresh();
    _changed();
  }

  void deleteCurrent() {
    final name = current;
    if (name == null) return;
    store.delete(name);
    buffers.remove(name);
    _forgetAnswers([name]);
    if (settings.scriptKeys.remove(name) != null) saveSettingsQuiet();
    _refresh();
    _closeEditor();
  }

  void _closeEditor() {
    current = null;
    dirty = false;
    _savedText = '';
    _setEditor('');
    if (scripts.isNotEmpty) {
      open(scripts.first);
    } else {
      _changed();
    }
  }

  /// Deletes every script and folder (the button in the menu of the list,
  /// after a confirmation). Their hotkeys, unsaved text and answers go too.
  void deleteAllScripts() {
    if (busy) return;
    try {
      store.deleteAll();
    } catch (e) {
      notify('Не удалось удалить все скрипты', '$e', level: 'error');
    }
    buffers.clear();
    settings.scriptKeys.clear();
    saveSettingsQuiet();
    _forgetAnswers([...answers.keys]);
    selectedFolder = '';
    collapsed.clear();
    _refresh();
    _closeEditor();
    notify('Скрипты удалены',
        scripts.isEmpty ? 'Список пуст' : 'Не удалось удалить: ${scripts.length}',
        level: scripts.isEmpty ? 'ok' : 'warn');
  }

  /// Scripts inside a folder (at any depth).
  List<String> scriptsIn(String folder) =>
      scripts.where((n) => n.startsWith('$folder/')).toList();

  /// Renames a folder; [rawName] is the new last part of its path.
  String? renameFolder(String path, String rawName) {
    final err = ScriptStore.validateName(rawName, allowPath: false);
    if (err != null) return err;
    final parent = ScriptStore.folderOf(path);
    final leaf = ScriptStore.sanitize(rawName);
    final to = parent.isEmpty ? leaf : '$parent/$leaf';
    if (to == path) return null;
    if (store.folderExists(to)) return 'Такая папка уже есть';
    final inside = scriptsIn(path);
    try {
      store.renameFolder(path, to);
    } catch (e) {
      return 'Не удалось переименовать: $e';
    }
    final before = [...scripts];
    final renames = {for (final old in inside) old: '$to${old.substring(path.length)}'};
    renames.forEach(_retarget);
    _fixRunScripts(renames, before);
    String fix(String f) =>
        f == path || f.startsWith('$path/') ? '$to${f.substring(path.length)}' : f;
    selectedFolder = fix(selectedFolder);
    final wasCollapsed = collapsed.map(fix).toSet();
    collapsed
      ..clear()
      ..addAll(wasCollapsed);
    saveSettingsQuiet();
    saveSchedule();
    saveAutoRules();
    _refresh();
    _changed();
    return null;
  }

  /// Deletes a folder with everything in it.
  void deleteFolder(String path) {
    final inside = scriptsIn(path);
    final hadCurrent = current != null && inside.contains(current);
    try {
      store.deleteFolderRecursive(path);
    } catch (e) {
      notify('Не удалось удалить папку', '$e', level: 'error');
      return;
    }
    for (final n in inside) {
      buffers.remove(n);
      settings.scriptKeys.remove(n);
    }
    _forgetAnswers(inside);
    saveSettingsQuiet();
    if (selectedFolder == path || selectedFolder.startsWith('$path/')) {
      selectedFolder = ScriptStore.folderOf(path);
    }
    _refresh();
    if (hadCurrent) {
      _closeEditor();
    } else {
      _changed();
    }
  }

  void selectFolder(String path) {
    selectedFolder = path;
    _changed();
  }

  void toggleFolder(String path) {
    if (!collapsed.remove(path)) collapsed.add(path);
    selectedFolder = path;
    _changed();
  }

  /// Creates a folder inside [selectedFolder].
  String? createFolder(String rawName) {
    final err = ScriptStore.validateName(rawName);
    if (err != null) return err;
    final clean = ScriptStore.sanitize(rawName);
    final path = selectedFolder.isEmpty ? clean : '$selectedFolder/$clean';
    if (store.folderExists(path)) return 'Такая папка уже есть';
    store.createFolder(path);
    _refresh();
    selectedFolder = path;
    _changed();
    return null;
  }

  /// Rewrites the bundled examples with their original text.
  void restoreExamples() {
    exampleScripts.forEach((name, src) {
      final full = '$examplesFolder/$name';
      store.write(full, src);
      buffers.remove(full);
      if (full == current) {
        _savedText = src;
        _setEditor(src);
        dirty = false;
      }
    });
    _refresh();
    notify('Примеры восстановлены', 'Папка «$examplesFolder» приведена к исходному виду',
        level: 'ok');
  }

  /// Adds (or brings back to the original text) the scripts that check
  /// the settings, folder "Проверки", and opens the first one.
  void addCheckScripts() {
    checkScripts.forEach((name, src) {
      final full = '$checksFolder/$name';
      store.write(full, src);
      buffers.remove(full);
      if (full == current) {
        _savedText = src;
        _setEditor(src);
        dirty = false;
      }
    });
    _refresh();
    if (!busy) open('$checksFolder/${checkScripts.keys.first}');
    notify('Скрипты-проверки добавлены',
        'Папка «$checksFolder»: ${checkScripts.length} скриптов. Что включить и что должно '
        'произойти — в комментариях в начале каждого',
        level: 'ok');
  }

  void insertAtCursor(String text) {
    final sel = editor.selection;
    final t = editor.text;
    var start = sel.isValid ? sel.start : t.length;
    var end = sel.isValid ? sel.end : t.length;
    if (start > end) (start, end) = (end, start);
    // Insert whole lines on their own line.
    var prefix = '';
    if (text.endsWith('\n') && start > 0 && t[start - 1] != '\n') prefix = '\n';
    final ins = '$prefix$text';
    editor.value = TextEditingValue(
      text: t.replaceRange(start, end, ins),
      selection: TextSelection.collapsed(offset: start + ins.length),
    );
  }
}

/// A run_script("…") call that a rename would change, for the window that
/// asks which ones to fix.
class RunScriptFix {
  final String script;
  final ScriptRefChange change;

  /// The line as it is now (trimmed), to show.
  final String text;
  const RunScriptFix(this.script, this.change, this.text);
}
