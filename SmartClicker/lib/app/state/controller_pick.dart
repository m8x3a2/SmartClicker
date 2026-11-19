// Taking a point, a colour or a region with the mouse (pick buttons, blocks,
// mini panel). By default over a stop frame of the screen: the click reaches
// no program and buttons under the cursor do not light up on hover.
part of 'app_controller.dart';

extension AppControllerPick on AppController {
  /// [mode]: 'point' — one click, coordinates to the clipboard; 'color' —
  /// one click, the colour to the clipboard; 'region' / 'image' — a
  /// rectangle (drawn with the mouse over the stop frame, or two corners
  /// marked with Ctrl). [done] — a block takes the result instead of the
  /// clipboard; [line] — the line of that block.
  void startPick(
      [String mode = 'point', void Function(List<String> values, String color)? done, int line = 0]) {
    if (busy) return;
    picking = true;
    pickMode = mode;
    pickCorner = null;
    _pickDone = done;
    _pickLine = line;
    _pickBtnDown = backend.isVkDown(_isRegionPick ? 0x11 : 0x01);
    _pickMouse = backend.isVkDown(0x01);
    _pickRight = backend.isVkDown(0x02);
    _pickDragging = false;
    _endFreeze();
    _pickCompacted = false;
    if (settings.pickFreeze) {
      if (!compact && backend.isMainVisible() && !backend.isMainMinimized()) {
        // The program's own window would cover what the user wants to pick:
        // it turns into the mini panel (with the cancel button) first, and
        // the screen freezes once it has shrunk.
        setCompact(true);
        _pickCompacted = compact;
        if (_pickCompacted) _freezeDelay = 12; // 25-ms ticks
      }
      if (_freezeDelay == 0) _freeze();
    }
    _changed();
  }

  bool get _isRegionPick => pickMode == 'region' || pickMode == 'image';

  /// What the pipette copies: the colour and the point in pixels and in
  /// percent — ready for a script or a chat with a neural network.
  static String colorPickText(CursorInfo c) =>
      '${c.hex}   ${c.x}, ${c.y} px   ${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%';

  /// The stop frame is shown now.
  bool get pickFrozen => _frozen != null;

  void cancelPick() {
    if (!picking) return;
    picking = false;
    _pickDone = null;
    _pictureToReplace = null;
    backend.hideFrame();
    _endFreeze();
    _restoreAfterPick();
    _changed();
  }

  /// What the user has to do now (banner and mini panel).
  String get pickHint {
    final frozen = pickFrozen;
    if (!_isRegionPick) {
      final what = pickMode == 'color' ? 'нужный цвет' : 'нужное место';
      return frozen
          ? 'Экран заморожен — кликните на $what, клик никуда не попадёт'
          : 'Кликните на $what';
    }
    if (frozen) {
      return pickCorner == null
          ? 'Обведите область мышью (или Ctrl в левом верхнем углу)'
          : 'Отпустите в правом нижнем углу (или кликните / Ctrl там)';
    }
    return pickCorner == null
        ? 'Наведите курсор на ЛЕВЫЙ ВЕРХНИЙ угол области и нажмите Ctrl'
        : 'Теперь на ПРАВЫЙ НИЖНИЙ угол — и снова Ctrl';
  }

  /// How to cancel (added to the hint).
  String get pickCancelHint => pickFrozen ? 'Esc или правая кнопка — отмена' : 'Esc — отмена';

  // ---- stop frame ----

  void _freeze() {
    _freezeDelay = 0;
    final v = backend.virtualScreen();
    if (v.w <= 0 || v.h <= 0) return;
    final px = backend.capture(v.x, v.y, v.w, v.h);
    if (px.length != v.w * v.h * 4) return; // a live pick, as without the setting
    for (var i = 3; i < px.length; i += 4) {
      px[i] = 255;
    }
    if (!backend.showFreeze(v.x, v.y, v.w, v.h, px)) return;
    _frozen = Bitmap(v.w, v.h, px);
    _frozenAt = (x: v.x, y: v.y);
    _loupeAt = null;
    _pickMouse = backend.isVkDown(0x01);
    _pickRight = backend.isVkDown(0x02);
    backend.watchMouseButtons(true);
    _pressesLeft = backend.mousePresses(0x01);
    _pressesRight = backend.mousePresses(0x02);
    _changed();
  }

  void _endFreeze() {
    if (_frozen != null) {
      backend.hideFreeze();
      backend.hideLoupe();
      backend.watchMouseButtons(false);
    }
    _frozen = null;
    _loupeAt = null;
    _freezeDelay = 0;
  }

  /// The main window came to the mini panel for the pick: back to normal.
  void _restoreAfterPick() {
    if (!_pickCompacted) return;
    _pickCompacted = false;
    if (compact) setCompact(false);
  }

  /// Colour of the stop frame at a screen point; null without one.
  int? _frozenPixel(int x, int y) {
    final f = _frozen;
    if (f == null) return null;
    final lx = x - _frozenAt.x, ly = y - _frozenAt.y;
    if (lx < 0 || ly < 0 || lx >= f.w || ly >= f.h) return null;
    final i = (ly * f.w + lx) * 4;
    return (f.bgra[i + 2] << 16) | (f.bgra[i + 1] << 8) | f.bgra[i];
  }

  /// A piece of the stop frame (what the user saw); null without one.
  Bitmap? _frozenCrop(int x, int y, int w, int h) {
    final f = _frozen;
    if (f == null) return null;
    final lx = x - _frozenAt.x, ly = y - _frozenAt.y;
    if (lx < 0 || ly < 0 || lx + w > f.w || ly + h > f.h) return null;
    final out = Uint8List(w * h * 4);
    for (var row = 0; row < h; row++) {
      final from = ((ly + row) * f.w + lx) * 4;
      out.setRange(row * w * 4, (row + 1) * w * 4, f.bgra, from);
    }
    return Bitmap(w, h, out);
  }

  double get _screenScale {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 1.0 : views.first.devicePixelRatio;
  }

  /// The magnifier next to the cursor (on the other side near the edges).
  void _showLoupe(Pt p) {
    final f = _frozen;
    if (f == null || _loupeAt == p) return;
    _loupeAt = p;
    final scale = _screenScale;
    final img = loupeImage(f, p.x - _frozenAt.x, p.y - _frozenAt.y,
        cells: 15, cell: math.max(6, (8 * scale).round()));
    final gap = (22 * scale).round();
    var x = p.x + gap, y = p.y + gap;
    if (x + img.w > _frozenAt.x + f.w) x = p.x - gap - img.w;
    if (y + img.h > _frozenAt.y + f.h) y = p.y - gap - img.h;
    backend.showLoupe(x, y, img.w, img.h, img.bgra);
  }

  // ---- polling (every 25 ms while picking) ----

  /// The left / right button went down since the last poll over the stop
  /// frame — also a click shorter than one poll (counted by the hook).
  bool _freshPress(int vk, bool down, bool wasDown) {
    final now = backend.mousePresses(vk);
    final counted = vk == 0x02 ? _pressesRight : _pressesLeft;
    if (vk == 0x02) {
      _pressesRight = now;
    } else {
      _pressesLeft = now;
    }
    return (down && !wasDown) || now != counted;
  }

  void _pollPick() {
    if (backend.isVkDown(0x1B)) return cancelPick();
    if (_freezeDelay > 0) {
      if (--_freezeDelay == 0) _freeze();
      return;
    }
    final p = backend.cursorPos();
    if (pickFrozen) {
      final right = backend.isVkDown(0x02);
      final rightPressed = _freshPress(0x02, right, _pickRight);
      _pickRight = right;
      if (rightPressed && backend.freezeAt(p.x, p.y)) return cancelPick();
      if (_tick % 4 == 0) backend.raisePickOverlays();
      _showLoupe(p);
    }
    if (_isRegionPick) return _pollRegion(p);
    final down = backend.isVkDown(0x01);
    final pressed = pickFrozen ? _freshPress(0x01, down, _pickBtnDown) : down && !_pickBtnDown;
    _pickBtnDown = down;
    if (!pressed) return;
    // A click in our own window (the mini panel) is not a pick.
    if (pickFrozen ? !backend.freezeAt(p.x, p.y) : backend.pidAt(p.x, p.y) == pid) return;
    final c = readCursor(); // the colour comes from the stop frame
    picking = false;
    _endFreeze(); // the windows under the point are real again
    final done = _pickDone;
    if (done != null) {
      _pickDone = null;
      final a = _pickArea(c.x, c.y);
      done([a.fx(c.x - a.x), a.fy(c.y - a.y)], c.hex);
      _pickCompacted = false;
      if (compact) setCompact(false);
      backend.activateSelf();
      notify('Точка взята', '${a.where}: ${c.x - a.x}, ${c.y - a.y} px   ·   цвет ${c.hex}', level: 'ok');
      _changed();
      return;
    }
    _restoreAfterPick();
    _changed();
    if (pickMode == 'color') {
      final text = AppControllerPick.colorPickText(c);
      Clipboard.setData(ClipboardData(text: text));
      notify('Цвет и точка скопированы', text, level: 'ok');
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

  /// A rectangle: drawn with the mouse over the stop frame (press, drag,
  /// release — or two clicks), or two corners marked with Ctrl.
  void _pollRegion(Pt p) {
    final ctrl = backend.isVkDown(0x11);
    final ctrlPressed = ctrl && !_pickBtnDown;
    _pickBtnDown = ctrl;
    var mousePressed = false, mouseReleased = false;
    if (pickFrozen) {
      final m = backend.isVkDown(0x01);
      final fresh = _freshPress(0x01, m, _pickMouse);
      mousePressed = fresh && backend.freezeAt(p.x, p.y);
      // a click shorter than a poll: pressed and already released
      mouseReleased = !m && (_pickMouse || fresh);
      _pickMouse = m;
    }
    final first = pickCorner;
    if (first != null) {
      // Live frame from the first corner to the cursor.
      backend.showFrame(math.min(first.x, p.x), math.min(first.y, p.y),
          (first.x - p.x).abs() + 1, (first.y - p.y).abs() + 1);
    }
    if (first == null) {
      if (ctrlPressed || mousePressed) {
        pickCorner = p;
        _pickDragging = mousePressed;
        _changed();
      }
      return;
    }
    final far = (p.x - first.x).abs() >= 3 && (p.y - first.y).abs() >= 3;
    final finish = ctrlPressed || mousePressed || (mouseReleased && _pickDragging && far);
    if (mouseReleased) _pickDragging = false;
    if (!finish) return;
    picking = false;
    backend.hideFrame();
    final x = math.min(first.x, p.x), y = math.min(first.y, p.y);
    final w = (first.x - p.x).abs() + 1, h = (first.y - p.y).abs() + 1;
    if (w < 3 || h < 3) {
      _pickDone = null;
      _endFreeze();
      _restoreAfterPick();
      notify('Область слишком маленькая', 'Отметьте два разных угла', level: 'warn');
      return;
    }
    // The picture is what the user saw: the stop frame, or the screen taken
    // before our own window comes to the front.
    final shot = _frozenCrop(x, y, w, h) ?? Bitmap(w, h, backend.capture(x, y, w, h));
    _endFreeze();
    _pickCompacted = false;
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
    if (_savePictureReplacement(shot, x, y)) {
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

  /// "x, y" of a screen point in the format of the settings.
  String formatXY(int x, int y) {
    if (!settings.recPercent) return '$x, $y';
    final s = backend.screenSize();
    String pc(int v, int total) => '${(v * 100 / total).toStringAsFixed(2)}%';
    return '${pc(x, s.w)}, ${pc(y, s.h)}';
  }

  String formatCoords(CursorInfo c) => settings.recPercent
      ? '${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%'
      : '${c.x}, ${c.y}';

  /// The cursor position and the colour under it (from the stop frame while
  /// it is shown: the screen itself shows the frame then).
  CursorInfo readCursor() {
    final p = backend.cursorPos();
    final s = backend.screenSize();
    return CursorInfo(p.x, p.y, s.w > 0 ? p.x * 100 / s.w : 0,
        s.h > 0 ? p.y * 100 / s.h : 0, _frozenPixel(p.x, p.y) ?? backend.pixel(p.x, p.y));
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
}
