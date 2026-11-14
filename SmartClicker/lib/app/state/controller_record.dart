// Recording user actions into code.
part of 'app_controller.dart';

extension AppControllerRecord on AppController {
  List<String> get _allHotkeys => [
        settings.stopKey,
        settings.stopKey2,
        settings.pauseKey,
        settings.recordKey,
        settings.pickKey,
        settings.runKey,
        settings.miniKey,
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
        {
          for (final k in AppControllerHotkeys.recordingHotkeys(settings))
            ...AppController.comboVks(k)
        },
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
        'Остальные клавиши, в том числе Esc и ${settings.pauseKey.toUpperCase()}, записываются');
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

  void stopRecording() {
    if (state != RunState.recording) return;
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
