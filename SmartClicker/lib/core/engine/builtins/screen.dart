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
        await this.sleep(math.max(interval, 10), jitter: false);
      }
    });

    _def('color_diff', (c) => ScriptRuntime.colorDiff(_color(c, c.arg(0)), _color(c, c.arg(1))));

    _def('avg_color', (c) {
      final a = _area();
      final x = _coord(c, c.arg(0), true, a, 'avg_color');
      final y = _coord(c, c.arg(1), false, a, 'avg_color');
      final w = math.max(1, _size(c, c.arg(2, 'w'), true, a, 'avg_color'));
      final h = math.max(1, _size(c, c.arg(3, 'h'), false, a, 'avg_color'));
      final px = backend.capture(x, y, w, h);
      var r = 0, g = 0, b = 0;
      final n = px.length ~/ 4;
      if (n == 0) return '#000000';
      for (var i = 0; i < n; i++) {
        b += px[i * 4];
        g += px[i * 4 + 1];
        r += px[i * 4 + 2];
      }
      return ScriptRuntime.hex(((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n));
    });

    _def('read_text', (c) => _ocr(c, _region(c, 0, 'read_text')), ['screen_text']);

    _def('text_in', (c) {
      final want = ScriptRuntime._loose(_s(c, c.arg(4, 'text'), 'text_in'));
      return ScriptRuntime._loose(_ocr(c, _region(c, 0, 'text_in'))).contains(want);
    }, ['has_text']);

    _def('wait_text', (c) async {
      final want = ScriptRuntime._loose(_s(c, c.arg(4, 'text'), 'wait_text'));
      final timeout = _nOr(c, c.opt('timeout'), 10000, 'timeout');
      final interval = _nOr(c, c.opt('interval'), 500, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        if (ScriptRuntime._loose(_ocr(c, _region(c, 0, 'wait_text'))).contains(want)) return true;
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return false;
        await this.sleep(math.max(interval, 50), jitter: false);
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
      File(path).writeAsBytesSync(
          pngEncode(Bitmap(r.w, r.h, backend.capture(r.x, r.y, r.w, r.h))));
      _images.remove(path);
      return path;
    });

    _def('find_image', (c) => _findImage(c, 1, 'find_image'));

    _def('wait_image', (c) async {
      final timeout = _nOr(c, c.opt('timeout'), 10000, 'timeout');
      final interval = _nOr(c, c.opt('interval'), 300, 'interval');
      final sw = Stopwatch()..start();
      while (true) {
        final hit = _findImage(c, 1, 'wait_image');
        if (hit != null) return hit;
        if (timeout > 0 && sw.elapsedMilliseconds >= timeout) return null;
        await this.sleep(math.max(interval, 50), jitter: false);
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
        if (sw.elapsedMilliseconds >= timeout) return false;
        await this.sleep(math.max(interval, 50), jitter: false);
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
