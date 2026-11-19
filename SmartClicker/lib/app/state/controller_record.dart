// Recording user actions into code.
part of 'app_controller.dart';

extension AppControllerRecord on AppController {
  List<String> get _allHotkeys => [
        settings.stopKey,
        settings.stopKey2,
        settings.pauseKey,
        settings.recordKey,
        settings.pickKey,
        settings.ghostKey,
        settings.markKey,
        settings.runKey,
        settings.miniKey,
        settings.clipKey,
        ...settings.scriptKeys.values,
      ];

  /// True when [combo] is already used by another action or script.
  /// [currentValue] is what the edited setting holds now (not a conflict).
  bool hotkeyTaken(String combo, String currentValue) {
    if (combo.isEmpty) return false;
    var count = _allHotkeys.where((k) => k == combo).length;
    if (currentValue == combo) count--;
    return count > 0;
  }

  /// Assigns (or with an empty [combo] removes) the hotkey of a script.
  void setScriptKey(String name, String combo) {
    if (combo.isEmpty) {
      settings.scriptKeys.remove(name);
    } else {
      settings.scriptKeys[name] = combo;
    }
    saveSettings();
  }

  Recorder _newRecorder() => Recorder(
        backend,
        _ownWindowActive,
        [
          for (final k in AppControllerHotkeys.recordingHotkeys(settings))
            AppController.comboVks(k)
        ],
        overOwnWindow: (x, y) => backend.pidAt(x, y) == pid,
      );

  bool _ownWindowActive() => backend.activeWindow()?.pid == pid;

  Future<void> toggleRecording() async {
    if (state == RunState.recording) {
      stopRecording();
      return;
    }
    if (state == RunState.recCountdown) {
      state = RunState.idle;
      _changed();
      return;
    }
    if (busy || current == null) return;
    state = RunState.recCountdown;
    final taken = AppControllerHotkeys.recordingHotkeys(settings).map((k) => k.toUpperCase());
    notify('Запись', '${taken.join(', ')} работают в SmartClicker и в запись не попадут. '
        'Остальные клавиши, в том числе Esc и ${settings.pauseKey.toUpperCase()}, записываются. '
        '${settings.ghostKey.toUpperCase()} — призрак: клики записываются, но не нажимаются');
    for (countdown = settings.recordDelaySec; countdown > 0; countdown--) {
      _changed();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (state != RunState.recCountdown) return;
    }
    _recorder = _newRecorder();
    _recorder.start();
    recordMs.value = 0;
    state = RunState.recording;
    _changed();
  }

  /// The "ghost" mode of a recording: the user's clicks and keys are
  /// recorded, but reach no program (record pressing "Send" without
  /// sending). A red frame around the screen shows it is on.
  void setGhost(bool on) {
    if (on == ghost) return;
    if (on && state != RunState.recording) return;
    if (on && !backend.setGhost(true)) {
      notify('Призрак недоступен', 'Не удалось перехватить мышь и клавиатуру', level: 'warn');
      return;
    }
    if (!on) backend.setGhost(false);
    ghost = on;
    try {
      backend.beep(on ? 'warn' : 'info');
    } catch (_) {}
    final s = backend.screenSize();
    if (on) {
      backend.showFrame(3, 3, s.w - 6, s.h - 6); // drawn outside: along the edges
      notify(
          '👻 Призрак включён',
          'Клики и клавиши записываются, но НЕ доходят до программ. '
              'Выключить — ${settings.ghostKey.toUpperCase()}, колесо мыши не перехватывается',
          level: 'warn');
    } else {
      backend.hideFrame();
      notify('Призрак выключен', 'Клики и клавиши снова доходят до программ', level: 'ok');
    }
    _changed();
  }

  /// The ghost of a run: the same key as for a recording, while a script
  /// works. Its clicks and keys reach no program, the marker shows where
  /// they would go and the log says «призрак: не нажато» — to check a run
  /// up to the important click without pressing it.
  /// The ghost for ONE action: the next click or key of the running script
  /// is only shown, then it is real again (Shift + the ghost key, Shift +
  /// click on 👻) — to skip exactly the important click.
  void setRunGhostOnce() {
    if (!isRunning || runGhost || runGhostOnce) return;
    runGhostOnce = true;
    _runner.ghostOnce();
    try {
      backend.beep('warn');
    } catch (_) {}
    final s = backend.screenSize();
    backend.showFrame(3, 3, s.w - 6, s.h - 6);
    _log('system', '👻 Призрак на одно действие: следующий клик или клавиша скрипта не нажмётся');
    notify('👻 Призрак на одно действие', 'Следующий клик или клавиша скрипта только покажется, дальше — по-настоящему',
        level: 'warn');
    _changed();
  }

  /// The engine skipped the one action of [setRunGhostOnce].
  void _ghostOnceDone() {
    if (!runGhostOnce) return;
    runGhostOnce = false;
    if (!runGhost) backend.hideFrame();
    notify('Призрак выключен', 'Одно действие пропущено, дальше клики настоящие', level: 'ok');
    _changed();
  }

  void setRunGhost(bool on) {
    if (on == runGhost) return;
    if (on && !isRunning) return;
    runGhostOnce = false;
    runGhost = on;
    _runner.setGhost(on);
    try {
      backend.beep(on ? 'warn' : 'info');
    } catch (_) {}
    if (on) {
      final s = backend.screenSize();
      backend.showFrame(3, 3, s.w - 6, s.h - 6); // drawn outside: along the edges
      _log('system', '👻 Призрак включён: клики и клавиши скрипта не нажимаются');
      notify(
          '👻 Призрак включён',
          'Скрипт работает дальше, но его клики и клавиши НЕ доходят до программ — '
              'только показываются. Выключить — ${settings.ghostKey.toUpperCase()}',
          level: 'warn');
    } else {
      backend.hideFrame();
      if (isRunning) _log('system', '👻 Призрак выключен: клики снова настоящие');
      notify('Призрак выключен', 'Клики и клавиши скрипта снова доходят до программ', level: 'ok');
    }
    _changed();
  }

  void stopRecording() {
    if (state != RunState.recording) return;
    setGhost(false);
    final code = _recorder.stop(RecordOptions(
      percent: settings.recPercent,
      smart: settings.recSmart,
      text: settings.recText,
      mode: recordModeOf(settings.recMode),
      dwellMs: settings.recDwellMs.clamp(100, 60000),
      window: settings.recWindow,
      requireWindow: settings.recRequireWindow,
      systemKeys: settings.recSystemKeys,
    ));
    state = RunState.idle;
    if (code.trim().isEmpty) {
      notify('Запись пуста', 'Не записано ни одного действия', level: 'warn');
    } else {
      final lines = '\n'.allMatches(code).length;
      // Recorded coordinates are screen-relative, so the block must not
      // inherit a window binding set earlier in the script.
      insertAtCursor(
          '// --- запись ${DateTime.now().toString().substring(0, 19)} ---\n'
          'use_screen()            // координаты записи — от всего экрана\n'
          'require_window(null)    // запись не привязана к одному окну\n'
          '$code');
      notify('Запись добавлена', 'В скрипт вставлено строк: $lines', level: 'ok');
    }
    _changed();
  }
}
