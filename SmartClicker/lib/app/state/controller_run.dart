// Running scripts: start, pause, stop, events of the engine, checks before
// the run and restarting after an error.
part of 'app_controller.dart';

extension AppControllerRun on AppController {
  /// Starts the open script. With [step] it pauses before every line.
  Future<void> run({bool step = false}) async {
    if (busy || current == null) return;
    final name = current!, source = editor.text;
    _stepStart = step;
    logs.clear();
    errorLine.value = 0;
    currentLine.value = 0;
    _restarts = 0;
    if (settings.checkBeforeRun && !_checkGate(source)) return;
    final answers = await _answersFor(name, source, interactive: true);
    if (answers == null) {
      _log('system', 'Запуск отменён');
      _changed();
      return;
    }
    if (busy) return; // something else started while the window was open
    final delay = settings.runDelaySec;
    if (delay > 0) {
      state = RunState.countdown;
      for (countdown = delay; countdown > 0; countdown--) {
        _changed();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (state != RunState.countdown) return; // cancelled
      }
    }
    await _start(name, source, answers);
  }

  /// Starts any script right away (used by the schedule). The version with
  /// unsaved edits is used if there is one.
  Future<bool> runByName(String name, {String reason = ''}) async {
    if (busy || !store.exists(name)) return false;
    _stepStart = false;
    logs.clear();
    errorLine.value = 0;
    currentLine.value = 0;
    _restarts = 0;
    if (reason.isNotEmpty) _log('system', reason);
    final source = name == current ? editor.text : (buffers[name] ?? store.read(name));
    // No window here: the user is busy elsewhere (a hotkey, the schedule…).
    final answers = await _answersFor(name, source, interactive: false);
    await _start(name, source, answers ?? const {});
    return true;
  }

  Future<void> _start(String name, String source, Map<String, Object?> answers) async {
    _runScript = name;
    _runSource = source;
    _runAnswers = answers;
    _runStarted = DateTime.now();
    vars.value = const [];
    changedVars.clear();
    state = RunState.running;
    if (settings.miniOnRun && !compact) setCompact(true, auto: true);
    _changed();
    _log(
      'system',
      '▶ Запуск "$name" в ${_clockText(_runStarted!)}${settings.dryRun ? ' — ТЕСТОВЫЙ РЕЖИМ (без кликов)' : ''}'
          '  ·  стоп: ${settings.stopKeysLabel}, пауза: ${settings.pauseKey.toUpperCase()}',
    );
    if (answers.isNotEmpty) _log('system', '❓ Ответы: ${describeAnswers(answers)}');
    try {
      await _runner.start(_engineConfig(name, source, answers));
    } catch (e) {
      _log('error', 'Не удалось запустить движок: $e');
      state = RunState.idle;
      _changed();
    }
  }

  /// What the engine needs for a run of [name] with [source].
  Map<String, Object?> _engineConfig(String name, String source, Map<String, Object?> answers) => {
    'main': name,
    'source': source,
    'step': _stepStart,
    'answers': answers,
    'breaks': name == current ? breaks.value.toList() : const <int>[],
    'watch': settings.bottomTab == 'vars',
    'showClicks': settings.showClicks,
    'allowPower': settings.allowPower,
    // Unsaved edits take part in the run: what you see is what runs.
    'scripts': {...store.all(), ...buffers, ?current: editor.text},
    'dryRun': settings.dryRun,
    'human': settings.human,
    'clickOffset': settings.clickOffset,
    'typeDelay': settings.typeDelayMs,
    'timeJitter': settings.timeJitterPct / 100,
    'maxRuntimeMs': settings.maxRuntimeMin * 60000,
    'maxLoops': settings.maxLoops,
    'dataFile': paths.dataFile,
    'filesDir': paths.files,
    'ocrEngine': settings.ocrEngine,
    'ocrDir': paths.ocr,
  };

  /// Full path of a picture named in a script (the way the engine finds
  /// it: in the files folder, ".png" added).
  String imagePath(String name) {
    final file = name.toLowerCase().endsWith('.png') ? name : '$name.png';
    final isAbs =
        file.startsWith('/') || file.startsWith('\\') || RegExp(r'^[A-Za-z]:').hasMatch(file);
    return isAbs ? file : '${paths.files}${Platform.pathSeparator}$file';
  }

  bool _imageExists(String name) => File(imagePath(name)).existsSync();

  /// Names of the saved pictures (files/*.png without the extension).
  List<String> pictureNames() {
    try {
      return Directory(paths.files)
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .where((n) => n.toLowerCase().endsWith('.png'))
          .map((n) => n.substring(0, n.length - 4))
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  /// Mistakes in [source] that are visible without running it.
  /// run_script("Имя") finds "Папка/Имя" too — the same search as the engine.
  List<Issue> checkSource(String source) {
    final all = _allScriptTexts();
    return checkScript(
      source,
      CheckContext(
        builtins: AppController.builtinNames,
        scriptSource: (n) => all[resolveScriptName(n, all.keys)],
        imageExists: _imageExists,
        scriptNames: all.keys.toList(),
      ),
    );
  }

  /// Checks before a run. Errors stop the run once; pressing Run again
  /// with the same text starts it anyway.
  bool _checkGate(String source) {
    if (_forceText == source) {
      _forceText = null;
      return true;
    }
    final issues = checkSource(source);
    _logIssues(issues);
    final errors = issues.where((i) => i.error).toList();
    if (errors.isEmpty) return true;
    _forceText = source;
    errorLine.value = errors.first.line;
    _log(
      'system',
      'Скрипт не запущен. Исправьте ошибки или нажмите «Запуск» ещё раз — '
          'тогда он запустится как есть',
    );
    notify(
      'Скрипт не запущен',
      '${errors.length == 1 ? 'Найдена ошибка' : 'Найдено ошибок: ${errors.length}'} — '
          '${errors.first}. Повторный «Запуск» — запустить как есть',
      level: 'warn',
    );
    _changed();
    return false;
  }

  void _logIssues(List<Issue> issues) {
    for (final i in issues) {
      _log(
        i.error ? 'error' : 'warn',
        '${i.error ? '✖ Ошибка' : '⚠ Внимание'}: ${i.message}',
        i.line,
      );
    }
  }

  /// "Check the script" command of the menu.
  void checkNow() {
    if (current == null || busy) return;
    logs.clear();
    errorLine.value = 0;
    final issues = checkSource(editor.text);
    _logIssues(issues);
    final errors = issues.where((i) => i.error).length;
    if (issues.isEmpty) {
      _log('system', '✔ Проверка: ошибок не найдено');
      notify('Проверка', 'Ошибок не найдено', level: 'ok');
    } else {
      final first = issues.firstWhere((i) => i.error, orElse: () => issues.first);
      if (errors > 0) errorLine.value = first.line;
      _log('system', 'Проверка: ошибок — $errors, замечаний — ${issues.length - errors}');
      notify(
        'Проверка',
        'Ошибок: $errors, замечаний: ${issues.length - errors}. Подробности в логе',
        level: errors > 0 ? 'error' : 'warn',
      );
    }
    _changed();
  }

  /// Starts the failed script again after a pause, if the settings allow.
  void _maybeRestart(String name, String source) {
    final max = settings.restartOnError;
    if (max <= 0) return;
    if (_restarts >= max) {
      _log('warn', '↻ Перезапусков было $max — больше не перезапускаю');
      notify(
        'Перезапуски кончились',
        '"$name" упал $max раз подряд после перезапуска и больше не запускается',
        level: 'warn',
      );
      _restarts = 0;
      return;
    }
    _restarts++;
    final delay = settings.restartDelaySec.clamp(1, 3600);
    _log('system', '↻ Перезапуск через $delay с (попытка $_restarts из $max)');
    // Countdown: the stop key and the Stop button cancel it.
    Future(() async {
      state = RunState.countdown;
      for (countdown = delay; countdown > 0; countdown--) {
        _changed();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (state != RunState.countdown) {
          _restarts = 0;
          return;
        }
      }
      state = RunState.idle;
      errorLine.value = 0;
      _stepStart = false;
      await _start(name, source, _runAnswers);
    });
  }

  /// "14.11 03:05:12" for the log.
  static String _clockText(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// "1 ч 05 мин", "3 мин 20 с", "4.2 с".
  static String _duration(int ms) => formatDuration(ms);

  /// The script that is running now (null when nothing runs).
  String? get runningScript => isRunning ? _runScript : null;

  /// The program closes while a script works: the run ends at once and goes
  /// to the history and the log as "прерван: программа закрыта".
  void interruptForExit() {
    if (state == RunState.countdown) state = RunState.idle;
    if (!isRunning) return;
    _closing = true;
    _runner.kill();
  }

  void _onDone(Map<String, Object?> e) {
    backend.releaseAll();
    backend.hideMarker();
    final status = _closing ? 'closed' : '${e['status']}';
    final name = _runScript ?? '?';
    final ms = (e['ms'] as num?)?.toInt() ?? 0;
    final err = e['error'] as String?;
    final line = (e['line'] as num?)?.toInt() ?? 0;
    final inOther = e['script'] as String?;
    final secs = (ms / 1000).toStringAsFixed(1);
    currentLine.value = 0;
    final began = _runStarted ?? DateTime.now();
    final ended = began.add(Duration(milliseconds: ms));

    String? errText;
    switch (status) {
      case 'ok':
        _log('system', '✔ Скрипт завершён в ${_clockText(ended)} — работал ${_duration(ms)}');
        notify('Скрипт завершён', '"$name" отработал за $secs с', level: 'ok');
      case 'stopped':
        _log('system', '⏹ Остановлен в ${_clockText(ended)} — работал ${_duration(ms)}');
      case 'closed':
        _log('warn', '⏹ Прерван в ${_clockText(ended)}: программа закрыта — работал ${_duration(ms)}');
      case 'killed':
        _log('warn', '⏹ Скрипт не отвечал и был остановлен принудительно');
        notify(
          'Принудительная остановка',
          '"$name" не ответил на стоп и был убит через $secs с. Все клавиши отпущены.',
          level: 'warn',
        );
      case 'limit':
        errText = err;
        _log('warn', '⏹ $err');
        notify('Сработала защита', '"$name": $err (работал $secs с)', level: 'warn');
      default:
        errText = inOther != null
            ? '[$inOther] строка $line: $err'
            : (line > 0 ? 'Строка $line: $err' : '$err');
        _log('error', '✖ $errText', inOther == null ? line : 0);
        if (inOther == null && name == current) errorLine.value = line;
        notify(
          'Ошибка в скрипте',
          '"$name" — $errText'
              '${settings.saveReports ? '. Отчёт: История → Запуски' : ''}',
          level: 'error',
        );
    }

    String? logFile;
    if (settings.saveLogs) logFile = _saveLogFile(name);
    String? report;
    if (settings.saveReports && (status == 'error' || status == 'killed')) {
      // The screen is taken right away: it shows what the script saw.
      report = _saveReport(
        name,
        statusLabels[status] ?? status,
        errText,
        other: inOther,
        shot: true,
      );
    }
    final rec = RunRecord(
      name,
      _runStarted ?? DateTime.now(),
      ms,
      status,
      errText,
      logFile,
      report,
    );
    lastRun = rec;
    history.insert(0, rec);
    while (history.length > settings.historySize.clamp(1, 10000)) {
      history.removeLast();
    }
    writeJson(paths.historyFile, history.map((r) => r.toJson()).toList());
    state = RunState.idle;
    final restart = status == 'error' || status == 'killed';
    if (status == 'ok' || status == 'stopped') _restarts = 0;
    final willRestart = restart && _restarts < settings.restartOnError;
    if (_autoCompact && !willRestart) {
      setCompact(false, activate: false);
    } else {
      _changed();
    }
    if (restart) _maybeRestart(name, _runSource);
  }

  String? _saveLogFile(String name) {
    try {
      final stamp = fileStamp(_runStarted ?? DateTime.now());
      final path =
          '${paths.logs}${Platform.pathSeparator}${stamp}_${ScriptStore.sanitize(name).replaceAll('/', '_')}.log';
      File(path).writeAsStringSync(logText());
      // Keep only the newest 100 run logs; the journal of program errors
      // is not one of them.
      final files =
          Directory(paths.logs)
              .listSync()
              .whereType<File>()
              .where((f) => f.path != paths.appErrorsFile)
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(100)) {
        f.deleteSync();
      }
      return path;
    } catch (_) {
      return null;
    }
  }
}
