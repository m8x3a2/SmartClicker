// Built-in functions: screen (pixels, colours, text recognition, pictures).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsScreen on ScriptRuntime {
  void _registerScreen() {
    _def('screen_size', (c) {
      final a = _area();
      return <String, Object?>{'w': a.w, 'h': a.h, 'x': a.x, 'y': a.y};
    });

    _def('pixel', (c) {
      final p = _point(c, 0, 'pixel');
      return ScriptRuntime.hex(backend.pixel(p.x, p.y));
    }, ['get_pixel', 'pixel_color']);

    _def('pixel_is', (c) {
      final p = _point(c, 0, 'pixel_is');
      final want = _color(c, c.arg(2, 'color'));
      final tol = _nOr(c, c.arg(3, 'tolerance'), 10, 'tolerance');
      return ScriptRuntime.colorDiff(backend.pixel(p.x, p.y), want) <= tol;
    });

    _def('wait_pixel', (c) async {
      final p = _point(c, 0, 'wait_pixel');
      final want = _color(c, c.arg(2, 'color'));
      final timeout = _nOr(c, c.opt('timeout'), 10000, 'timeout');
      final tol = _nOr(c, c.opt('tolerance'), 10, 'tolerance');
      final interval = _nOr(c, c.opt('interval'), 100, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        if (ScriptRuntime.colorDiff(backend.pixel(p.x, p.y), want) <= tol) return true;
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return false;
        await this.sleep(math.max(interval, 10), jitter: false, react: true);
      }
    });

    // Waits until the area changes against how it was at the start (a page
    // loaded, a window or text appeared). true — changed, false — timeout.
    _def('wait_change', (c) async {
      final r = _region(c, 0, 'wait_change');
      final o = _changeOptions(c, 'wait_change');
      final start = backend.capture(r.x, r.y, r.w, r.h);
      final sw = Stopwatch()..start();
      while (true) {
        await this.sleep(o.interval, jitter: false, react: true);
        final now = backend.capture(r.x, r.y, r.w, r.h);
        if (changedShare(start, now, r.w, r.h, tolerance: o.tolerance) * 100 >= o.percent) return true;
        if (o.timeout > 0 && sw.elapsedMilliseconds >= o.timeout) return false;
      }
    });

    // Waits until the area stops changing for still: (1 s by default): an
    // animation ended, a neural network finished typing its answer.
    _def('wait_still', (c) async {
      final r = _region(c, 0, 'wait_still');
      final o = _changeOptions(c, 'wait_still');
      final still = _nOr(c, c.opt('still'), 1000, 'still').round();
      var prev = backend.capture(r.x, r.y, r.w, r.h);
      final sw = Stopwatch()..start();
      final calm = Stopwatch()..start();
      while (true) {
        await this.sleep(o.interval, jitter: false, react: true);
        final now = backend.capture(r.x, r.y, r.w, r.h);
        if (changedShare(prev, now, r.w, r.h, tolerance: o.tolerance) * 100 >= o.percent) calm.reset();
        prev = now;
        if (calm.elapsedMilliseconds >= still) return true;
        if (o.timeout > 0 && sw.elapsedMilliseconds >= o.timeout) return false;
      }
    });

    // by: "rgb" (largest channel difference), "hue" (degrees, light and
    // shadow do not change it), "bright" (brightness).
    _def('color_diff', (c) => colorDistance(_color(c, c.arg(0)), _color(c, c.arg(1)),
        by: _colorBy(c, 'color_diff')));

    // mode: "avg" (default), "median" (a cursor or a popup over a part of the
    // area does not shift it), "main" (the most common colour).
    _def('avg_color', (c) {
      final a = _area();
      final x = _coord(c, c.arg(0), true, a, 'avg_color');
      final y = _coord(c, c.arg(1), false, a, 'avg_color');
      final w = math.max(1, _size(c, c.arg(2, 'w'), true, a, 'avg_color'));
      final h = math.max(1, _size(c, c.arg(3, 'h'), false, a, 'avg_color'));
      final px = backend.capture(x, y, w, h);
      if (px.isEmpty) return '#000000';
      return ScriptRuntime.hex(areaColor(px, mode: _colorMode(c, 'avg', 'avg_color')));
    }, ['area_color']);

    _def('hue', (c) => hueOf(_color(c, c.arg(0, 'color'))));
    _def('brightness', (c) => brightnessOf(_color(c, c.arg(0, 'color'))));
    _def('saturation', (c) => saturationOf(_color(c, c.arg(0, 'color'))));

    // Loose comparison of recognized text (core/vision/text_match.dart).
    _def('similar', (c) => textMatches(
        _plain(c.arg(0, 'text')), _s(c, c.arg(1, 'pattern'), 'similar'), _matchRules(c, 'similar')));
    _def('similarity', (c) => textSimilarity(_plain(c.arg(0, 'text')),
        _s(c, c.arg(1, 'pattern'), 'similarity'), _matchRules(c, 'similarity')));

    _def('read_text', (c) => _ocr(c, _region(c, 0, 'read_text')), ['screen_text']);

    _def('text_in', (c) {
      final want = _s(c, c.arg(4, 'text'), 'text_in');
      return _textFound(c, _ocr(c, _region(c, 0, 'text_in')), want, 'text_in');
    }, ['has_text']);

    _def('wait_text', (c) async {
      final want = _s(c, c.arg(4, 'text'), 'wait_text');
      final timeout = _nOr(c, c.opt('timeout'), 10000, 'timeout');
      final interval = _nOr(c, c.opt('interval'), 500, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        if (_textFound(c, _ocr(c, _region(c, 0, 'wait_text')), want, 'wait_text')) return true;
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return false;
        await this.sleep(math.max(interval, 50), jitter: false, react: true);
      }
    });

    _def('read_number', (c) {
      final text = _ocr(c, _region(c, 0, 'read_number'))
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll(',', '.')
          .replaceAll('−', '-');
      final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(text);
      if (m == null) return null;
      final v = double.parse(m.group(0)!);
      return v == v.roundToDouble() ? v.toInt() : v;
    });

    _def('screenshot', (c) {
      final name = _s(c, c.arg(0, 'name'), 'screenshot');
      final r = _region(c, 1, 'screenshot');
      final path = _imagePath(name);
      File(path).writeAsBytesSync(pngEncode(Bitmap(r.w, r.h, backend.capture(r.x, r.y, r.w, r.h)),
          text: originText(r.x, r.y, r.w, r.h)));
      _images.remove(path);
      _imageOrigins.remove(path);
      return path;
    });

    _def('find_image', (c) => _findImage(c, 1, 'find_image'));

    // Every copy of the picture (coins, enemies, cells): a list of places
    // in reading order, [] — none; max: 100.
    _def('find_images', (c) => _findImages(c, 1, 'find_images'));

    _def('wait_image', (c) async {
      final timeout = _nOr(c, c.opt('timeout'), 10000, 'timeout');
      final interval = _nOr(c, c.opt('interval'), 300, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        final hit = _findImage(c, 1, 'wait_image');
        if (hit != null) return hit;
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return null;
        await this.sleep(math.max(interval, 50), jitter: false, react: true);
      }
    });

    _def('click_image', (c) async {
      final timeout = _nOr(c, c.opt('timeout'), 0, 'timeout');
      final interval = _nOr(c, c.opt('interval'), 300, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        final hit = _findImage(c, 1, 'click_image');
        if (hit != null) {
          await _click(CallCtx([hit], c.named, c.line));
          return true;
        }
        if (sw.elapsedMilliseconds >= timeout) {
          if (dryRun) _mapAction('картинка "${stringify(c.arg(0))}" не найдена — клика нет', null, 'miss');
          return false;
        }
        await this.sleep(math.max(interval, 50), jitter: false, react: true);
      }
    });

    _def('find_color', (c) {
      final want = _color(c, c.arg(0, 'color'));
      final a = _area();
      final x = c.args.length > 1 ? _coord(c, c.arg(1), true, a, 'find_color') : a.x;
      final y = c.args.length > 2 ? _coord(c, c.arg(2), false, a, 'find_color') : a.y;
      final w = c.args.length > 3 ? _size(c, c.arg(3), true, a, 'find_color') : a.w;
      final h = c.args.length > 4 ? _size(c, c.arg(4), false, a, 'find_color') : a.h;
      final tol = _nOr(c, c.opt('tolerance'), 10, 'tolerance');
      final px = backend.capture(x, y, w, h);
      final wr = (want >> 16) & 0xFF, wg = (want >> 8) & 0xFF, wb = want & 0xFF;
      for (var i = 0; i + 3 < px.length; i += 4) {
        if ((px[i] - wb).abs() <= tol &&
            (px[i + 1] - wg).abs() <= tol &&
            (px[i + 2] - wr).abs() <= tol) {
          final idx = i ~/ 4;
          return <String, Object?>{
            'x': x + idx % w - a.x,
            'y': y + idx ~/ w - a.y,
          };
        }
      }
      return null;
    });
  }
}
