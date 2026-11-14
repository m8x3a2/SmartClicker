// Input with checks (test mode, bound window), human-like movement, held keys;
// data kept between runs (save_data / load_data).
part of 'runtime.dart';

extension ScriptRuntimeRuntimeInput on ScriptRuntime {
  bool _windowOk() {
    final q = _requiredWindow;
    if (q == null) return true;
    final a = backend.activeWindow();
    if (a == null) return false;
    // The handle counts too: a title such as "file - Notepad" may change.
    return a.matches(q) || (_requiredHandle != null && a.handle == _requiredHandle);
  }

  /// require_window(focus: true): brings the required window to the front.
  /// True when it is in front now.
  Future<bool> _bringRequired() async {
    final w = _findWindow(_requiredWindow!);
    if (w == null) return false;
    _requiredHandle = w.handle;
    if (_windowOk()) return true;
    log('Окно "${w.title}" не спереди — вывожу вперёд', 'action');
    await _focus(w.handle);
    await this.sleep(150, jitter: false);
    return _windowOk();
  }

  /// Must precede every input action. Returns false in test mode (the action
  /// is only logged). With require_window the action waits until that
  /// window is active (focus: true — brings it to the front first).
  Future<bool> _guardInput(String description, {Pt? at}) async {
    _checkLimits();
    if (!_windowOk()) {
      if (dryRun && _requireFocus) {
        log('[тест] вывести вперёд окно "$_requiredWindow"', 'action');
      } else if (!_requireFocus || !await _bringRequired()) {
        log(
            _requireFocus
                ? 'Окно "$_requiredWindow" не удалось вывести вперёд (нет окна?) — жду…'
                : 'Окно "$_requiredWindow" не активно — жду…',
            'warn');
        _emitLine();
        var tries = 0;
        while (!_windowOk()) {
          await this.sleep(200, jitter: false);
          // Keep trying every 2 s: the window may appear or unminimize.
          if (_requireFocus && ++tries % 10 == 0 && await _bringRequired()) break;
        }
        log('Окно "$_requiredWindow" снова активно, продолжаю');
      }
    }
    if (showClicks && at != null) {
      // Let the user see where the action is about to happen.
      emit({'t': 'mark', 'x': at.x, 'y': at.y});
      await this.sleep(400, jitter: false);
    }
    if (dryRun) {
      log('[тест] $description', 'action');
      return false;
    }
    log(description, 'action');
    return true;
  }

  Future<void> _moveSmooth(Pt to, num duration, {bool curved = true}) async {
    final from = backend.cursorPos();
    final steps = math.max(1, duration ~/ 8);
    final sw = Stopwatch()..start();
    final pts = human.path(from.x, from.y, to.x, to.y, steps, curved: curved);
    for (var i = 0; i < pts.length; i++) {
      backend.moveTo(pts[i].x, pts[i].y);
      final due = duration * (i + 1) / pts.length;
      final wait = due - sw.elapsedMilliseconds;
      if (wait >= 1) await this.sleep(wait, jitter: false);
    }
  }

  Future<void> _goto(CallCtx c, Pt p) async {
    var d = _nOr(c, c.opt('duration') ?? c.opt('move'), -1, 'duration');
    if (d < 0) {
      if (humanMode) {
        final from = backend.cursorPos();
        final dist = math.sqrt(math.pow(p.x - from.x, 2) + math.pow(p.y - from.y, 2));
        d = dist < 3 ? 0 : human.moveDuration(dist.toDouble());
      } else {
        d = 0;
      }
    }
    if (d <= 0) {
      backend.moveTo(p.x, p.y);
    } else {
      await _moveSmooth(p, d, curved: humanMode);
    }
  }

  /// A mouse button down: keys sent just before may still be unread by the
  /// window, and a click elsewhere takes the focus away — they would be lost.
  Future<void> _buttonDown(String b) async {
    await _settleKeys();
    _button(b, true);
  }

  void _button(String b, bool down) {
    backend.mouseButton(b, down);
    down ? _heldButtons.add(b) : _heldButtons.remove(b);
  }

  void _key(String k, bool down) {
    backend.keyEvent(k, down);
    down ? _heldKeys.add(k) : _heldKeys.remove(k);
    _keysSent();
  }

  void _keysSent() {
    _keysUnsettled++;
    _sinceKeys
      ..reset()
      ..start();
  }

  /// Before the focus may move to another window (a click, focus_window):
  /// gives the window time after the last key to read what was sent.
  /// Programs take keys with a lag that grows with every key, and a window
  /// that loses the focus drops what it has not read yet (the Windows 11
  /// Notepad lost the last 1–4 of 40 keys with 100 ms, none with 400 ms):
  /// 100 ms + 8 ms per key since the last such pause, at most 0.5 s.
  Future<void> _settleKeys() async {
    if (!_sinceKeys.isRunning) return;
    final need = math.min(500, 100 + 8 * _keysUnsettled);
    final left = need - _sinceKeys.elapsedMilliseconds;
    _sinceKeys.stop();
    _keysUnsettled = 0;
    if (left > 0) await this.sleep(left, jitter: false);
  }

  /// Brings window [handle] to the front (after the keys sent are read).
  Future<bool> _focus(int handle) async {
    await _settleKeys();
    // Cross-thread foreground activation may complete after the API returns.
    // Yield between checks so the recipient can process activation messages.
    for (var attempt = 0; attempt < 3; attempt++) {
      backend.focusWindow(handle);
      for (var poll = 0; poll < 5; poll++) {
        await this.sleep(50, jitter: false);
        if (backend.activeWindow()?.handle == handle) return true;
      }
    }
    return false;
  }

  Future<void> _press(String button, num holdMs) async {
    await _buttonDown(button);
    try {
      await this.sleep(holdMs, jitter: false);
    } finally {
      _button(button, false);
    }
  }

  num _clickHold() => humanMode ? 45 + rng.nextInt(70) : 20;

  Future<Object?> _click(CallCtx c, {String? button, int count = 1}) async {
    final hasPoint = c.args.isNotEmpty || c.named.containsKey('x');
    final btn = button ?? _s(c, c.opt('button', 'left'), 'button');
    final n = _nOr(c, c.opt('count'), count, 'count').round();
    final hold = c.opt('hold');
    Pt? p;
    if (hasPoint) p = _scatter(c, _point(c, 0, 'click'));
    final what = n == 2 ? 'двойной клик' : 'клик';
    final desc =
        '$what${btn == 'left' ? '' : ' ($btn)'}${p != null ? ' → ${_fmtPt(p)}' : ''}';
    if (!await _guardInput(desc, at: p)) return null;
    if (p != null) {
      await _goto(c, p);
      // Let the target notice the cursor (hover) before the button goes down.
      await this.sleep(humanMode ? 40 + rng.nextInt(50) : 15, jitter: false);
    }
    for (var i = 0; i < n; i++) {
      if (i > 0) await this.sleep(humanMode ? 70 + rng.nextInt(60) : 60, jitter: false);
      await _press(btn, hold != null ? _n(c, hold, 'hold') : _clickHold());
    }
    return null;
  }

  List<String> _combo(CallCtx c, String spec) {
    final s = spec.trim().toLowerCase();
    final parts = s == '+' ? ['plus'] : s.split('+').map((p) => p.trim()).toList();
    if (s.endsWith('++')) {
      parts
        ..removeWhere((p) => p.isEmpty)
        ..add('plus');
    }
    for (final p in parts) {
      if (!vkByName.containsKey(p)) {
        c.fail('Неизвестная клавиша "$p" в "$spec". '
            'Примеры: "enter", "ctrl+c", "f5", "a", "left"');
      }
    }
    return parts;
  }

  File get _dataFile => File(cfg['dataFile'] as String? ?? 'data.json');

  Map<String, Object?> _loadData() {
    if (_data != null) return _data!;
    try {
      final f = _dataFile;
      if (f.existsSync()) {
        return _data = Map<String, Object?>.from(jsonDecode(f.readAsStringSync()) as Map);
      }
    } catch (_) {}
    return _data = {};
  }

  String _path(String p) {
    final isAbs = p.startsWith('/') || p.startsWith('\\') || RegExp(r'^[A-Za-z]:').hasMatch(p);
    if (isAbs) return p;
    final dir = cfg['filesDir'] as String? ?? '.';
    Directory(dir).createSync(recursive: true);
    return '$dir${Platform.pathSeparator}$p';
  }

  Object? _jsonSafe(Object? v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is List) return v.map(_jsonSafe).toList();
    if (v is Map) return v.map((k, x) => MapEntry('$k', _jsonSafe(x)));
    return stringify(v);
  }

  /// Finds a window. For "process|title" the title may have changed since
  /// the script was written (editors put the document text into the title),
  /// so fall back to the topmost window of that program.
  WindowInfo? _findWindow(String q) {
    final all = backend.windows();
    // A tiny window of the same program (a pop-up, a tooltip) is taken only
    // when there is no real one.
    WindowInfo? tiny;
    for (final w in all) {
      if (!w.matches(q)) continue;
      if (w.w >= 100 && w.h >= 60) return w;
      tiny ??= w;
    }
    if (tiny != null) return tiny;
    final bar = q.indexOf('|');
    if (bar > 0) {
      final proc = q.substring(0, bar).trim();
      for (final w in all) {
        if (w.matches('$proc|')) {
          log('Окно "$q" не найдено по заголовку — беру верхнее окно '
              'программы $proc: "${w.title}"', 'warn');
          return w;
        }
      }
    }
    return null;
  }
}
