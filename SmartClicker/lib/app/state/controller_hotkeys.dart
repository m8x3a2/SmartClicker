// Polling every 25 ms: global hotkeys (and which of them other programs must
// not get), F6 — a click at the cursor into the script. Picks: controller_pick.dart.
part of 'app_controller.dart';

extension AppControllerHotkeys on AppController {
  bool _comboDown(String combo) {
    final vks = AppController.comboVks(combo);
    return vks.isNotEmpty &&
        vks.every(backend.isUserKeyDown) &&
        !extraModifierHeld(vks, backend.isUserKeyDown);
  }

  bool _pressed(String combo) {
    if (combo.isEmpty) return false;
    final down = _comboDown(combo);
    final hit = AppControllerHotkeys.freshPress(_hotkeyState, combo, down) ||
        AppControllerHotkeys.quickPress(
            _hotkeyFired, combo, backend.comboPresses(AppController.comboVks(combo)), down);
    // Caps Lock of a hotkey ("capslock+q") also switched capital letters on
    // or off; it is switched back once released (see _onPoll) — only when
    // the hotkey does something now (otherwise the keys go on as usual).
    if (hit &&
        combo.contains('+') &&
        AppController.comboVks(combo).contains(0x14) &&
        !_hotkeysSuspended &&
        AppControllerHotkeys.heldBackHotkeys(settings, state,
                hasScript: current != null, active: true)
            .contains(combo)) {
      _capsRestore = true;
    }
    // The main key of a held-back hotkey does not reach the program, so it
    // sees Alt (or Win) pressed and released alone: Alt opens the menu
    // (Notepad: «Файл»), Win — the Start menu. A key of our own while they
    // are still down makes them "used" (F24 — no program uses it).
    if (hit &&
        (combo.contains('alt') || combo.contains('win')) &&
        settings.holdBackHotkeys &&
        !_hotkeysSuspended &&
        AppControllerHotkeys.heldBackHotkeys(settings, state, hasScript: current != null)
            .contains(combo)) {
      backend.keyEvent('f24', true);
      backend.keyEvent('f24', false);
    }
    return hit;
  }

  /// A held-back combo was pressed and let go between two polls (the hook
  /// counted it, [down] is false already). The first count of a combo, or
  /// one from a new table of combos, is only remembered.
  static bool quickPress(
      Map<String, ({int gen, int count})> last, String combo, ({int gen, int count})? now, bool down) {
    if (now == null) {
      last.remove(combo);
      return false;
    }
    final was = last[combo];
    last[combo] = now;
    return !down && was != null && was.gen == now.gen && was.count != now.count;
  }

  /// The combo went down since the last poll. A combo seen for the first
  /// time is not a press: a hotkey that was just assigned is still held
  /// (the dialog closes on the key press) and must not fire at once.
  static bool freshPress(Map<String, bool> last, String combo, bool down) {
    final was = last[combo] ?? down;
    last[combo] = down;
    return down && !was;
  }

  /// Hotkeys that do something during the recording: they are neither
  /// recorded nor passed to the program. All other keys (Esc, pause, keys of
  /// scripts) do nothing then, so they go to the program and get recorded.
  static List<String> recordingHotkeys(Settings s) =>
      [s.stopKey, s.recordKey, s.pickKey, s.miniKey, s.ghostKey, s.markKey]
          .where((k) => k.isNotEmpty)
          .toList();

  /// Hotkeys to keep away from other programs right now: only the ones that
  /// do something in this [state] (F12 with nothing running stays F12).
  /// [active] — the same list even when holding back is off in the settings.
  static List<String> heldBackHotkeys(Settings s, RunState state,
      {required bool hasScript, bool active = false, bool picking = false}) {
    // Esc cancels a pick and must not close something in the program below.
    if (picking) return ['esc', ..._heldBack(s, state, hasScript: hasScript, active: active)];
    return _heldBack(s, state, hasScript: hasScript, active: active);
  }

  static List<String> _heldBack(Settings s, RunState state,
      {required bool hasScript, required bool active}) {
    if (!s.holdBackHotkeys && !active) return const [];
    final idle = state == RunState.idle;
    final running = state == RunState.running || state == RunState.paused;
    if (state == RunState.recording) return recordingHotkeys(s);
    final recording = state == RunState.recCountdown;
    return [
      if (!idle) s.stopKey,
      if (running || state == RunState.countdown) s.stopKey2,
      if (running) s.pauseKey,
      if (running) s.ghostKey,
      if ((idle && hasScript) || recording) s.recordKey,
      s.pickKey,
      s.markKey,
      s.miniKey,
      if (s.clipHistory) s.clipKey,
      if (idle && hasScript) s.runKey,
      if (idle) ...s.scriptKeys.values,
    ].where((k) => k.isNotEmpty).toList();
  }

  void _syncHeldBackKeys() {
    final keys = _hotkeysSuspended
        ? const <String>[]
        : AppControllerHotkeys.heldBackHotkeys(settings, state, hasScript: current != null, picking: picking);
    final ok = backend.holdBackKeys([for (final k in keys) AppController.comboVks(k)]);
    if (!ok && !_holdBackWarned) {
      _holdBackWarned = true;
      notify('Горячие клавиши', 'Не удалось перехватить клавиатуру: горячие клавиши работают, '
          'но доходят и до активной программы', level: 'warn');
    }
  }

  /// Hotkeys are ignored while the user assigns a new one in settings.
  void suspendHotkeys() => _hotkeysSuspended = true;

  void resumeHotkeys() {
    // Keys still held from the capture must not fire as a fresh press.
    for (final k in _allHotkeys) {
      _hotkeyState[k] = _comboDown(k);
    }
    _hotkeyFired.clear(); // presses while suspended are not hotkeys
    _hotkeysSuspended = false;
  }

  /// F6: inserts a click at the cursor position. If the script is bound to
  /// a window at the caret (use_window) and the cursor is over that window,
  /// the coordinates are relative to it; otherwise screen coordinates.
  void pickPoint() {
    final c = readCursor();
    final under = backend.windowAt(c.x, c.y);
    final usable = under != null && under.pid != pid && !under.isShell;
    final canInsert = current != null && !isRunning;

    String? bound;
    if (canInsert) {
      final sel = editor.selection;
      final caret = sel.isValid ? sel.start : editor.text.length;
      bound = bindingAt(editor.text.substring(0, caret));
    }

    WindowInfo? target;
    var prefix = '';
    if (usable) {
      if (bound != null && under.matches(bound)) {
        target = under;
      } else if (settings.recWindow) {
        target = under;
        final sel = windowSelector(under, backend.windows())
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"');
        prefix = 'use_window("$sel")\n';
      }
    }
    final area = target == null ? null : backend.clientRect(target.handle);
    if (area == null || area.w <= 0 || area.h <= 0) {
      target = null;
      prefix = bound != null ? 'use_screen()\n' : '';
    }

    final String coords, where;
    if (target != null && area != null) {
      final rx = c.x - area.x, ry = c.y - area.y;
      coords = settings.recPercent
          ? '${(rx * 100 / area.w).toStringAsFixed(2)}%, ${(ry * 100 / area.h).toStringAsFixed(2)}%'
          : '$rx, $ry';
      where = 'в окне "${target.title}": $rx, $ry';
    } else {
      coords = settings.recPercent
          ? '${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%'
          : '${c.x}, ${c.y}';
      where = 'на экране: ${c.x}, ${c.y}';
    }
    if (canInsert) {
      insertAtCursor('${prefix}click($coords)  // $where, цвет ${c.hex}\n');
    }
    notify('Точка выбрана', '$where\n$coords   цвет ${c.hex}', level: 'ok');
  }

  void _onPoll() {
    _tick++;
    if (_tick % 200 == 0) _checkSchedule(); // every 5 seconds
    if (_tick % 40 == 20) _checkAutorun(); // every second
    if (_tick % 40 == 0) _syncTray();
    if (_tick % 80 == 60) _checkDiskChanges(); // scripts changed by other programs
    if (_tick % 20 == 7) _checkClipboard(); // clipboard history
    if (_tick == 1200 || _tick % 144000 == 0) _checkAutoBackup(); // 30 s after the start, then hourly
    if (_tick % 40 == 30) {
      _checkRequests(); // --run / --stop from other programs
      _checkFileRules(); // scripts started when a file changes
      _checkGuards(); // a program crashed or hung while its script works
      if (isRunning) _writeState();
    }
    // Countdown of the delayed automation in the banner (and turning it on).
    if (_tick % 40 == 10 && automationHeldUntil != null && !automationOn) _changed();
    _hideAfterAutostart();
    if (_capsRestore && !backend.isUserKeyDown(0x14)) {
      _capsRestore = false;
      backend.keyEvent('capslock', true); // own input: no hotkey, not recorded
      backend.keyEvent('capslock', false);
    }
    // Another copy of the program showed our window (see SingleInstance):
    // it is no longer in the tray.
    if (_tick % 8 == 0 && hiddenToTray && backend.isMainVisible()) {
      hiddenToTray = false;
      _syncTray();
      _changed();
    }
    if (_tick % 8 == 4 &&
        settings.trayOnMinimize &&
        !hiddenToTray &&
        !compact &&
        backend.isMainMinimized()) {
      hideToTray();
    }
    _syncHeldBackKeys();
    _checkCornerStop();
    if (!_hotkeysSuspended) {
      if (_pressed(settings.stopKey)) stop(hotkey: true);
      if (_pressed(settings.stopKey2) &&
          (isRunning || state == RunState.countdown)) {
        stop(hotkey: true);
      }
      if (_pressed(settings.pauseKey)) togglePause();
      if (_pressed(settings.recordKey)) toggleRecording();
      if (_pressed(settings.pickKey)) pickPoint();
      if (_pressed(settings.ghostKey)) {
        if (state == RunState.recording) setGhost(!ghost);
        // Shift + the ghost key: only the next action of the script
        if (isRunning && !settings.ghostKey.contains('shift') && _comboDown('shift') && !runGhost) {
          setRunGhostOnce();
        } else if (isRunning) {
          setRunGhost(!runGhost);
        }
      }
      if (_pressed(settings.markKey)) toggleLandmark();
      if (_pressed(settings.miniKey)) toggleCompact();
      if (_pressed(settings.clipKey) && settings.clipHistory) _onClipHotkey();
      // Hotkey starts have no countdown: the user is already in the right
      // window when pressing the key.
      if (_pressed(settings.runKey) &&
          state == RunState.idle &&
          current != null) {
        runByName(current!, via: 'key');
      }
      for (final e in settings.scriptKeys.entries.toList()) {
        if (_pressed(e.value) && state == RunState.idle) {
          if (!store.exists(e.key)) {
            notify('Клавиша ${e.value.toUpperCase()}',
                'Скрипт "${e.key}" не найден', level: 'warn');
          } else if (!e.value.contains('shift') && _comboDown('shift')) {
            runWithQuestions(e.key, via: 'key'); // Shift + key: ask the questions first
          } else {
            runByName(e.key, via: 'key');
          }
        }
      }
    }
    if (state == RunState.recording && _tick % 4 == 0) {
      recordMs.value = _recorder.elapsedMs;
    }
    if (picking) _pollPick();
    if ((trackCursor || compact || picking || state == RunState.recording) &&
        _tick % 4 == 0) {
      cursor.value = readCursor();
    }
  }
}
