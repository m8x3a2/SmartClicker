// Built-in functions: mouse (click, move, drag, hold, scroll, mouse_path...).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsMouse on ScriptRuntime {
  void _registerMouse() {
    _def('click', (c) => _click(c), ['tap']);
    _def('double_click', (c) => _click(c, count: 2));
    _def('right_click', (c) => _click(c, button: 'right'));
    _def('middle_click', (c) => _click(c, button: 'middle'));

    _def('move', (c) async {
      final p = _scatter(c, _point(c, 0, 'move'));
      if (!await _guardInput('курсор → ${_fmtPt(p)}')) return null;
      await _goto(c, p);
      return null;
    }, ['move_to']);

    _def('mouse_down', (c) async {
      final btn = _s(c, c.opt('button', 'left'), 'button');
      Pt? p;
      if (c.args.isNotEmpty) p = _point(c, 0, 'mouse_down');
      if (!await _guardInput('зажать кнопку мыши ($btn)')) return null;
      if (p != null) await _goto(c, p);
      await _buttonDown(btn);
      return null;
    });

    _def('mouse_up', (c) async {
      final btn = _s(c, c.opt('button', 'left'), 'button');
      Pt? p;
      if (c.args.isNotEmpty) p = _point(c, 0, 'mouse_up');
      if (!await _guardInput('отпустить кнопку мыши ($btn)')) return null;
      if (p != null) await _goto(c, p);
      _button(btn, false);
      return null;
    });

    _def('drag', (c) async {
      final a = _area();
      final p1 = (
        x: _coord(c, c.arg(0), true, a, 'drag'),
        y: _coord(c, c.arg(1), false, a, 'drag')
      );
      final p2 = (
        x: _coord(c, c.arg(2), true, a, 'drag'),
        y: _coord(c, c.arg(3), false, a, 'drag')
      );
      final dur = _nOr(c, c.arg(4, 'duration'), 400, 'duration');
      final btn = _s(c, c.opt('button', 'left'), 'button');
      if (!await _guardInput(
          'перетащить ${_fmtPt(p1)} → ${_fmtPt(p2)} за ${dur.round()} мс', at: p1)) {
        return null;
      }
      final s1 = _scatter(c, p1), s2 = _scatter(c, p2);
      backend.moveTo(s1.x, s1.y);
      await this.sleep(30, jitter: false);
      await _buttonDown(btn);
      try {
        await this.sleep(40, jitter: false);
        await _moveSmooth(s2, math.max(dur, 16), curved: humanMode);
        await this.sleep(40, jitter: false);
      } finally {
        _button(btn, false);
      }
      return null;
    }, ['swipe']);

    _def('hold', (c) async {
      final p = _scatter(c, _point(c, 0, 'hold'));
      final dur = _nOr(c, c.arg(2, 'duration'), 1000, 'duration');
      final btn = _s(c, c.opt('button', 'left'), 'button');
      if (!await _guardInput('удержать ${_fmtPt(p)} на ${dur.round()} мс', at: p)) {
        return null;
      }
      await _goto(c, p);
      await _buttonDown(btn);
      try {
        if (humanMode) {
          // Finger/hand tremor: tiny drifts while holding.
          final sw = Stopwatch()..start();
          while (sw.elapsedMilliseconds < dur) {
            await this.sleep(math.min(120, dur - sw.elapsedMilliseconds), jitter: false);
            backend.moveTo(p.x + rng.nextInt(3) - 1, p.y + rng.nextInt(3) - 1);
          }
        } else {
          await this.sleep(dur, jitter: false);
        }
      } finally {
        _button(btn, false);
      }
      return null;
    }, ['long_press']);

    _def('scroll', (c) async {
      final amount = _n(c, c.arg(0, 'amount'), 'scroll').round();
      Pt? p;
      if (c.args.length >= 3) p = _point(c, 1, 'scroll');
      if (!await _guardInput('колесо мыши: $amount')) return null;
      if (p != null) backend.moveTo(p.x, p.y);
      final step = amount > 0 ? 1 : -1;
      for (var i = 0; i < amount.abs(); i++) {
        backend.scroll(step, horizontal: c.opt('horizontal') == true);
        if (i < amount.abs() - 1) await this.sleep(humanMode ? 30 + rng.nextInt(40) : 15, jitter: false);
      }
      return null;
    });

    // Replays a recorded trajectory: "x,y,ms x,y,ms ..." where ms is the
    // delay before moving to that point.
    _def('mouse_path', (c) async {
      final spec = _s(c, c.arg(0, 'points'), 'mouse_path');
      final percent = c.opt('unit') == '%';
      final speed = _nOr(c, c.opt('speed'), 1, 'speed');
      if (speed <= 0) c.fail('mouse_path: speed должен быть больше 0');
      final a = _area();
      final pts = <({int x, int y, num dt})>[];
      for (final item in spec.trim().split(RegExp(r'\s+'))) {
        if (item.isEmpty) continue;
        final f = item.split(',');
        final x = f.length == 3 ? num.tryParse(f[0]) : null;
        final y = f.length == 3 ? num.tryParse(f[1]) : null;
        final dt = f.length == 3 ? num.tryParse(f[2]) : null;
        if (x == null || y == null || dt == null) {
          c.fail('mouse_path: точка "$item" должна иметь вид x,y,мс');
        }
        pts.add((
          x: _coord(c, percent ? Percent(x.toDouble()) : x, true, a, 'mouse_path'),
          y: _coord(c, percent ? Percent(y.toDouble()) : y, false, a, 'mouse_path'),
          dt: dt / speed,
        ));
      }
      if (pts.isEmpty) return null;
      if (!await _guardInput('траектория мыши: ${pts.length} точек')) return null;
      final sw = Stopwatch()..start();
      num due = 0;
      for (final p in pts) {
        due += p.dt;
        final wait = due - sw.elapsedMilliseconds;
        if (wait >= 1) {
          await this.sleep(wait, jitter: false);
        } else {
          _checkLimits();
        }
        backend.moveTo(p.x, p.y);
      }
      return null;
    });

    _def('mouse_pos', (c) {
      final p = backend.cursorPos();
      final a = _area();
      return <String, Object?>{
        'x': p.x - a.x,
        'y': p.y - a.y,
        'px': a.w > 0 ? (p.x - a.x) * 100 / a.w : 0,
        'py': a.h > 0 ? (p.y - a.y) * 100 / a.h : 0,
      };
    });
  }
}
