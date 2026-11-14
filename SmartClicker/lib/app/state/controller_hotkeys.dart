// Polling every 25 ms: global hotkeys (and which of them other programs must
// not get), taking a point or a region with a click (F6, pick buttons of blocks).
part of 'app_controller.dart';

extension AppControllerHotkeys on AppController {
  bool _comboDown(String combo) {
    final vks = AppController.comboVks(combo);
    return vks.isNotEmpty && vks.every(backend.isUserKeyDown);
  }

  bool _pressed(String combo) =>
      combo.isNotEmpty && AppControllerHotkeys.freshPress(_hotkeyState, combo, _comboDown(combo));

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
      [s.stopKey, s.recordKey, s.pickKey, s.miniKey].where((k) => k.isNotEmpty).toList();

  /// Hotkeys to keep away from other programs right now: only the ones that
  /// do something in this [state] (F12 with nothing running stays F12).
  static List<String> heldBackHotkeys(Settings s, RunState state,
      {required bool hasScript}) {
    if (!s.holdBackHotkeys) return const [];
    final idle = state == RunState.idle;
    final running = state == RunState.running || state == RunState.paused;
    if (state == RunState.recording) return recordingHotkeys(s);
    final recording = state == RunState.recCountdown;
    return [
      if (!idle) s.stopKey,
      if (running || state == RunState.countdown) s.stopKey2,
      if (running) s.pauseKey,
      if ((idle && hasScript) || recording) s.recordKey,
      s.pickKey,
      s.miniKey,
      if (idle && hasScript) s.runKey,
      if (idle) ...s.scriptKeys.values,
    ].where((k) => k.isNotEmpty).toList();
  }

  void _syncHeldBackKeys() {
    final keys = _hotkeysSuspended
        ? const <String>[]
        : AppControllerHotkeys.heldBackHotkeys(settings, state, hasScript: current != null);
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
    _hotkeysSuspended = false;
  }

  void startPick(
      [String mode = 'point', void Function(List<String> values, String color)? done, int line = 0]) {
    if (busy) return;
    picking = true;
    pickMode = mode;
    pickCorner = null;
    _pickDone = done;
    _pickLine = line;
    _pickBtnDown = backend.isVkDown(mode == 'point' ? 0x01 : 0x11);
    _changed();
  }

  void cancelPick() {
    if (!picking) return;
    picking = false;
    _pickDone = null;
    _pictureToReplace = null;
    backend.hideFrame();
    _changed();
  }

  /// What the user has to do now (banner and mini panel).
  String get pickHint {
    if (pickMode == 'point') return 'Кликните в нужное место';
    return pickCorner == null
        ? 'Наведите курсор на ЛЕВЫЙ ВЕРХНИЙ угол области и нажмите Ctrl'
        : 'Теперь на ПРАВЫЙ НИЖНИЙ угол — и снова Ctrl';
  }

  void _pollRegion() {
    final down = backend.isVkDown(0x11);
    final pressed = down && !_pickBtnDown;
    _pickBtnDown = down;
    final p = backend.cursorPos();
    final first = pickCorner;
    if (first != null) {
      // Live frame from the first corner to the cursor.
      backend.showFrame(math.min(first.x, p.x), math.min(first.y, p.y),
          (first.x - p.x).abs() + 1, (first.y - p.y).abs() + 1);
    }
    if (!pressed) return;
    if (first == null) {
      pickCorner = p;
      _changed();
      return;
    }
    picking = false;
    backend.hideFrame();
    final x = math.min(first.x, p.x), y = math.min(first.y, p.y);
    final w = (first.x - p.x).abs() + 1, h = (first.y - p.y).abs() + 1;
    if (w < 3 || h < 3) {
      _pickDone = null;
      notify('Область слишком маленькая', 'Отметьте два разных угла', level: 'warn');
      return;
    }
    final done = _pickDone;
    if (done != null) {
      _pickDone = null;
      final a = _pickArea(x, y);
      done([a.fx(x - a.x), a.fy(y - a.y), a.fx(w), a.fy(h)], '');
      if (compact) setCompact(false);
      backend.activateSelf();
      _changed();
      return;
    }
    // The picture is taken before our own window comes to the front.
    final shot = Bitmap(w, h, backend.capture(x, y, w, h));
    if (_savePictureReplacement(shot)) {
      if (compact) setCompact(false);
      backend.activateSelf();
      openPage('vision');
      _changed();
      return;
    }
    Clipboard.setData(ClipboardData(text: formatRegion(x, y, w, h)));
    if (compact) setCompact(false);
    backend.activateSelf();
    captured.value = ScreenCapture(x, y, w, h, shot);
    openPage('vision');
    _changed();
  }

  void openPage(String page) => pageRequest.value = page;

  /// "x, y, w, h" in the format chosen in the settings (pixels or percent).
  String formatRegion(int x, int y, int w, int h) {
    if (!settings.recPercent) return '$x, $y, $w, $h';
    final s = backend.screenSize();
    String pc(int v, int total) => '${(v * 100 / total).toStringAsFixed(2)}%';
    return '${pc(x, s.w)}, ${pc(y, s.h)}, ${pc(w, s.w)}, ${pc(h, s.h)}';
  }

  String formatCoords(CursorInfo c) => settings.recPercent
      ? '${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%'
      : '${c.x}, ${c.y}';

  void _pollPick() {
    if (backend.isVkDown(0x1B)) {
      cancelPick();
      return;
    }
    if (pickMode != 'point') return _pollRegion();
    final down = backend.isVkDown(0x01);
    final pressed = down && !_pickBtnDown;
    _pickBtnDown = down;
    if (!pressed) return;
    final c = readCursor();
    if (backend.pidAt(c.x, c.y) == pid) return; // a click in our own window
    picking = false;
    final done = _pickDone;
    if (done != null) {
      _pickDone = null;
      final a = _pickArea(c.x, c.y);
      done([a.fx(c.x - a.x), a.fy(c.y - a.y)], c.hex);
      backend.activateSelf();
      notify('Точка взята', '${a.where}: ${c.x - a.x}, ${c.y - a.y} px   ·   цвет ${c.hex}', level: 'ok');
      _changed();
      return;
    }
    final inWindow = settings.pickFromWindow ? windowPickText(c) : null;
    if (inWindow != null) {
      Clipboard.setData(ClipboardData(text: inWindow.code));
      notify('Скопировано: клик в окне', '${inWindow.code}\n${inWindow.where}   ·   цвет ${c.hex}',
          level: 'ok');
      return;
    }
    final text = formatCoords(c);
    Clipboard.setData(ClipboardData(text: text));
    notify(
        'Координаты скопированы',
        '$text\n${c.x}, ${c.y} px   ·   ${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%   ·   цвет ${c.hex}',
        level: 'ok');
  }

  /// A click at [c] counted from the window under it, as a line to paste:
  /// `with_window("notepad") { click(50%, 20%) }`; null over the desktop,
  /// the taskbar or our own window.
  ({String code, String where})? windowPickText(CursorInfo c) {
    final under = backend.windowAt(c.x, c.y);
    if (under == null || under.pid == pid || under.isShell) return null;
    final area = backend.clientRect(under.handle);
    if (area == null || area.w <= 0 || area.h <= 0) return null;
    final rx = c.x - area.x, ry = c.y - area.y;
    if (rx < 0 || ry < 0 || rx >= area.w || ry >= area.h) return null; // on the title bar
    final coords = settings.recPercent
        ? '${(rx * 100 / area.w).toStringAsFixed(2)}%, ${(ry * 100 / area.h).toStringAsFixed(2)}%'
        : '$rx, $ry';
    final sel = windowSelector(under, backend.windows())
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    return (
      code: 'with_window("$sel") { click($coords) }',
      where: 'в окне "${under.title}": $rx, $ry px',
    );
  }

  /// The area coordinates picked for a block are counted from: the window
  /// the script is bound to above the block (when the point is in it) or
  /// the screen; formatters give pixels or percent as in the settings.
  ({int x, int y, String where, String Function(int) fx, String Function(int) fy}) _pickArea(
      int px, int py) {
    var ox = 0, oy = 0, w = 0, h = 0;
    var where = 'на экране';
    final lines = editor.text.split('\n');
    final bound = _pickLine > 1 ? bindingAt(lines.take(_pickLine - 1).join('\n')) : null;
    final under = bound == null ? null : backend.windowAt(px, py);
    final area = under != null && under.matches(bound!) ? backend.clientRect(under.handle) : null;
    if (area != null && area.w > 0 && area.h > 0) {
      (ox, oy, w, h) = (area.x, area.y, area.w, area.h);
      where = 'в окне "${under!.title}"';
    } else {
      final s = backend.screenSize();
      (w, h) = (s.w, s.h);
    }
    String f(int v, int total) => settings.recPercent && total > 0
        ? '${(v * 100 / total).toStringAsFixed(2)}%'
        : '$v';
    return (x: ox, y: oy, where: where, fx: (v) => f(v, w), fy: (v) => f(v, h));
  }

  CursorInfo readCursor() {
    final p = backend.cursorPos();
    final s = backend.screenSize();
    return CursorInfo(p.x, p.y, s.w > 0 ? p.x * 100 / s.w : 0,
        s.h > 0 ? p.y * 100 / s.h : 0, backend.pixel(p.x, p.y));
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
    _hideAfterAutostart();
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
      if (_pressed(settings.miniKey)) toggleCompact();
      // Hotkey starts have no countdown: the user is already in the right
      // window when pressing the key.
      if (_pressed(settings.runKey) &&
          state == RunState.idle &&
          current != null) {
        runByName(current!);
      }
      for (final e in settings.scriptKeys.entries.toList()) {
        if (_pressed(e.value) && state == RunState.idle) {
          if (!store.exists(e.key)) {
            notify('Клавиша ${e.value.toUpperCase()}',
                'Скрипт "${e.key}" не найден', level: 'warn');
          } else if (!e.value.contains('shift') && _comboDown('shift')) {
            runWithQuestions(e.key); // Shift + key: ask the questions first
          } else {
            runByName(e.key);
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
