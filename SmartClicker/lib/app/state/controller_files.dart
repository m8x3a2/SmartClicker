// Export and import of scripts as ZIP, "share a script" (with its pictures
// and the scripts it runs), opening folders.
part of 'app_controller.dart';

extension AppControllerFiles on AppController {
  void openFolder(String path) {
    if (Platform.isWindows) {
      Process.start('explorer', [path]);
    }
  }

  /// Every script as it is now: unsaved edits included.
  Map<String, String> _allScriptTexts() => {
        ...store.all(),
        ...buffers,
        ?current: editor.text,
      };

  /// Writes every script into a ZIP archive chosen by the user.
  void exportScripts() {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = DateTime.now();
    final path = backend.pickFile(
        save: true,
        title: 'Экспорт скриптов',
        defaultName:
            'SmartClicker-скрипты-${d.year}-${two(d.month)}-${two(d.day)}.zip');
    if (path == null) return;
    try {
      final all = _allScriptTexts();
      File(path).writeAsBytesSync(zipEncode({
        for (final e in all.entries)
          '${e.key}${ScriptStore.ext}': utf8.encode(e.value),
      }));
      notify('Экспорт готов', 'Скриптов: ${all.length}\n$path', level: 'ok');
    } catch (e) {
      notify('Не удалось экспортировать', '$e', level: 'error');
    }
  }

  /// What "Share" of [name] would put into the archive.
  SharePlan sharePlan(String name) => planShare(name, _allScriptTexts(),
      pictureExists: _imageExists, pictureReaders: pictureReaders);

  /// One ZIP with the script, its pictures and the scripts it runs.
  void shareScript(String name) {
    final plan = sharePlan(name);
    final path = backend.pickFile(
        save: true,
        title: 'Поделиться скриптом',
        defaultName: '${ScriptStore.baseOf(name)}.zip');
    if (path == null) return;
    try {
      File(path).writeAsBytesSync(encodeShare(plan, _allScriptTexts(), (p) {
        try {
          return File(imagePath(p)).readAsBytesSync();
        } catch (_) {
          return null;
        }
      }));
      notify(
          'Архив готов',
          'Скриптов: ${plan.scripts.length}, картинок: ${plan.pictures.length}'
              '${plan.missing.isEmpty ? '' : '. Нет картинок (в архив не попали): ${plan.missing.join(', ')}'}'
              '\n$path',
          level: plan.missing.isEmpty ? 'ok' : 'warn');
    } catch (e) {
      notify('Не удалось сохранить архив', '$e', level: 'error');
    }
  }

  /// Asks for an archive and reads it: what would be added, what clashes,
  /// which commands can do harm. Null if cancelled or unreadable.
  ImportPlan? readImport() {
    final path = backend.pickFile(save: false, title: 'Импорт из ZIP');
    if (path == null) return null;
    try {
      final archive = readShare(Uint8List.fromList(File(path).readAsBytesSync()));
      if (archive.scripts.isEmpty) {
        notify('В архиве нет скриптов', 'Файлы .cks не найдены в $path', level: 'warn');
        return null;
      }
      return planImport(archive,
          existingScript: (n) => store.exists(n)
              ? (n == current ? editor.text : (buffers[n] ?? store.read(n)))
              : null,
          existingPicture: (n) {
            final f = File(imagePath(n));
            return f.existsSync() ? f.readAsBytesSync() : null;
          });
    } catch (e) {
      notify('Не удалось прочитать архив', '$e', level: 'error');
      return null;
    }
  }

  /// Adds what [plan] says; renamed items get "(импорт)" and the imported
  /// scripts are fixed to use the new names. Opens the main script.
  void applyImport(ImportPlan plan) {
    try {
      final out = resolveImport(plan);
      final replaced = {
        for (final i in plan.items)
          if (!i.picture && i.action == ImportAction.replace) i.name,
      };
      out.scripts.forEach((name, text) {
        if (replaced.contains(name)) {
          // My version stays in the undo history: open it, Ctrl+Z brings it back.
          final mine = name == current ? editor.text : (buffers.remove(name) ?? store.read(name));
          historyOf(name).record(TextEditingValue(text: mine));
        }
        store.write(name, text);
        if (name == current) {
          _savedText = text;
          _setEditor(text);
          dirty = false;
        }
      });
      out.pictures.forEach((name, bytes) {
        final f = File(imagePath(name));
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(bytes);
      });
      _refresh();
      final main = plan.archive.main;
      final opened = main == null ? null : (out.scriptNames[main] ?? main);
      if (opened != null && store.exists(opened) && !busy) open(opened);
      final skipped = plan.items.length - out.scripts.length - out.pictures.length;
      final replacedAll = plan.items.where((i) => i.action == ImportAction.replace).length;
      notify(
          out.scripts.isEmpty && out.pictures.isEmpty ? 'Ничего не добавлено' : 'Импорт готов',
          'Скриптов: ${out.scripts.length}, картинок: ${out.pictures.length}'
              '${replacedAll > 0 ? ', из них заменено: $replacedAll (свой вариант скрипта — Ctrl+Z после открытия)' : ''}'
              '${skipped > 0 ? ', не добавлено (уже есть): $skipped' : ''}',
          level: 'ok');
    } catch (e) {
      notify('Не удалось импортировать', '$e', level: 'error');
    }
    _changed();
  }

  /// Runs one line of a paused script and pauses again.
  void step() {
    if (state != RunState.paused) return;
    _runner.step();
    state = RunState.running;
    _changed();
  }

  void togglePause() {
    if (_batch != null) return; // a dry run of a folder has no pause
    if (state == RunState.running) {
      _runner.pause();
      state = RunState.paused;
      _log('system', '⏸ Пауза');
    } else if (state == RunState.paused) {
      _runner.resume();
      state = RunState.running;
      _log('system', '▶ Продолжение');
    }
    _changed();
  }

  /// Stop button / kill-switch.
  void stop({bool hotkey = false}) {
    if (_batch != null) {
      _cancelBatch();
      return;
    }
    switch (state) {
      case RunState.countdown:
        state = RunState.idle;
        _log('system', 'Запуск отменён');
        _changed();
      case RunState.running || RunState.paused:
        _log('system', hotkey ? '⏹ Стоп по горячей клавише' : '⏹ Стоп');
        _runner.stop(grace: Duration(milliseconds: hotkey ? 150 : 400));
        // Whatever the script was holding must be released right now.
        backend.releaseAll();
      case RunState.recCountdown:
        state = RunState.idle;
        _changed();
      case RunState.recording:
        stopRecording();
      case RunState.idle:
        break;
    }
  }

  void _onEngineEvent(Map<String, Object?> e) {
    switch (e['t']) {
      case 'log':
        _log('${e['lv']}', '${e['m']}', (e['l'] as int?) ?? 0);
      case 'line':
        // Highlight lines only when the running script is the one on screen.
        if (_runScript == current) currentLine.value = (e['l'] as int?) ?? 0;
      case 'paused':
        // Step mode or a breakpoint stopped before a line.
        if (_runScript == current) currentLine.value = (e['l'] as int?) ?? 0;
        if (e['why'] == 'break') {
          _log('system',
              '⏸ Точка останова. Значения — вкладка «Переменные»; дальше — «Продолжить» или «Шаг»',
              (e['l'] as int?) ?? 0);
        }
        state = RunState.paused;
        _changed();
      case 'vars':
        _onVars(e['rows'] as List? ?? const []);
      case 'mark':
        backend.showMarker((e['x'] as num).toInt(), (e['y'] as num).toInt());
        _markerTimer?.cancel();
        _markerTimer =
            Timer(const Duration(milliseconds: 550), backend.hideMarker);
      case 'notify':
        notify('${e['title']}', '${e['body']}');
        _log('info', '🔔 ${e['title']}: ${e['body']}');
      case 'done':
        _onDone(e);
    }
  }
}
