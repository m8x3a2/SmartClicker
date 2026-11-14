// Reading arguments of built-in functions: numbers, coordinates, regions, colours.
part of 'runtime.dart';

extension ScriptRuntimeRuntimeArgs on ScriptRuntime {
  num _n(CallCtx c, Object? v, String what) {
    if (v is num) return v;
    if (v is RangeVal) {
      if (v.lo is int && v.hi is int) {
        final lo = math.min(v.lo, v.hi).toInt(), hi = math.max(v.lo, v.hi).toInt();
        return lo + rng.nextInt(hi - lo + 1);
      }
      return v.lo + rng.nextDouble() * (v.hi - v.lo);
    }
    if (v is String) {
      final p = num.tryParse(v.trim());
      if (p != null) return p;
    }
    c.fail('$what: ожидалось число, получено ${stringify(v, quote: true)}');
  }

  num _nOr(CallCtx c, Object? v, num def, String what) =>
      v == null ? def : _n(c, v, what);

  String _s(CallCtx c, Object? v, String what) {
    if (v is String) return v;
    if (v == null) c.fail('$what: ожидалась строка');
    return stringify(v);
  }

  /// Area that coordinates are relative to: the screen or a bound window.
  Rect4 _area() {
    if (_originWindow != null) {
      final r = backend.clientRect(_originWindow!);
      if (r != null && r.w > 0 && r.h > 0) return r;
    }
    final s = backend.screenSize();
    return (x: 0, y: 0, w: s.w, h: s.h);
  }

  int _coord(CallCtx c, Object? v, bool isX, Rect4 a, String what) {
    if (v is Percent) {
      return ((isX ? a.x : a.y) + (isX ? a.w : a.h) * v.value / 100).round();
    }
    if (v == null) c.fail('$what: не задана координата ${isX ? 'x' : 'y'}');
    return ((isX ? a.x : a.y) + _n(c, v, what)).round();
  }

  int _size(CallCtx c, Object? v, bool isX, Rect4 a, String what) {
    if (v is Percent) return ((isX ? a.w : a.h) * v.value / 100).round();
    return _n(c, v, what).round();
  }

  Pt _point(CallCtx c, int i, String what) {
    final a = _area();
    final first = c.arg(i);
    if (first is Map) {
      // Accept a point object such as the result of find_color().
      return (
        x: _coord(c, first['x'], true, a, what),
        y: _coord(c, first['y'], false, a, what)
      );
    }
    return (
      x: _coord(c, c.arg(i, 'x'), true, a, what),
      y: _coord(c, c.arg(i + 1, 'y'), false, a, what)
    );
  }

  /// Rectangle given as x, y, w, h starting at argument [i]; the whole
  /// area (screen or bound window) when the arguments are missing.
  Rect4 _region(CallCtx c, int i, String what) {
    final a = _area();
    if (c.args.length <= i) return a;
    if (c.args.length < i + 4) {
      c.fail('$what: область задаётся четырьмя числами — x, y, ширина, высота');
    }
    return (
      x: _coord(c, c.arg(i), true, a, what),
      y: _coord(c, c.arg(i + 1), false, a, what),
      w: math.max(1, _size(c, c.arg(i + 2), true, a, what)),
      h: math.max(1, _size(c, c.arg(i + 3), false, a, what)),
    );
  }

  String _ocr(CallCtx c, Rect4 r) {
    final lang = _s(c, c.opt('lang', ''), 'lang');
    final scale = _nOr(c, c.opt('scale'), 0, 'scale').round();
    try {
      final explicit = c.opt('engine');
      var engine = ocrEngineId(
          _s(c, explicit ?? cfg['ocrEngine'] ?? 'paddle', 'engine'));
      // Chosen in the program but not installed: fall back to the fast one.
      if (engine == 'paddle' &&
          explicit == null &&
          !PaddleOcr.installed(cfg['ocrDir'] as String? ?? '')) {
        if (!_ocrFallbackLogged) {
          _ocrFallbackLogged = true;
          log('Точное распознавание (PaddleOCR) не установлено — читаю быстрым '
              'встроенным в Windows', 'warn');
        }
        engine = 'windows';
      }
      if (engine == 'windows') {
        return backend.readText(r.x, r.y, r.w, r.h, lang: lang, scale: scale);
      }
      return ocrBitmap(
          backend, Bitmap(r.w, r.h, backend.capture(r.x, r.y, r.w, r.h)),
          engine: engine, ocrDir: cfg['ocrDir'] as String? ?? '');
    } on ScriptError {
      rethrow;
    } catch (e) {
      c.fail('Распознавание текста: $e');
    }
  }

  String _imagePath(String name) =>
      _path(name.toLowerCase().endsWith('.png') ? name : '$name.png');

  Bitmap _image(CallCtx c, String name, String what) {
    final path = _imagePath(name);
    final cached = _images[path];
    if (cached != null) return cached;
    final f = File(path);
    if (!f.existsSync()) {
      c.fail('$what: картинка "$name" не найдена ($path). Сохраните её командой '
          'screenshot("$name", x, y, w, h) или кнопкой «Вырезать картинку»');
    }
    try {
      return _images[path] = pngDecode(f.readAsBytesSync());
    } on FormatException catch (e) {
      c.fail('$what: "$name" — ${e.message}');
    }
  }

  /// Centre of the found image, relative to the current area, or null.
  Map<String, Object?>? _findImage(CallCtx c, int i, String what) {
    final img = _image(c, _s(c, c.arg(0, 'name'), what), what);
    final r = _region(c, i, what);
    final tol = _nOr(c, c.opt('tolerance'), 20, 'tolerance').round();
    final scale = _scaleRange(c, c.opt('scale'), what);
    final hay = Bitmap(r.w, r.h, backend.capture(r.x, r.y, r.w, r.h));
    ({int x, int y, int w, int h, double scale})? hit;
    if (scale == null) {
      final p = findBitmap(hay, img, tolerance: tol);
      if (p != null) hit = (x: p.x, y: p.y, w: img.w, h: img.h, scale: 1.0);
    } else {
      hit = findBitmapScaled(hay, img,
          tolerance: tol,
          minScale: scale.lo,
          maxScale: scale.hi,
          center: scale.center);
    }
    if (hit == null) return null;
    final a = _area();
    final left = r.x + hit.x - a.x, top = r.y + hit.y - a.y;
    return {
      'x': left + hit.w ~/ 2,
      'y': top + hit.h ~/ 2,
      'left': left,
      'top': top,
      'w': hit.w,
      'h': hit.h,
      'scale': (hit.scale * 1000).round() / 1000,
    };
  }

  /// `scale:` of the image functions: null — exact size; a number — about
  /// that scale (±6%); a range `0.5..2` or `[0.5, 2]`; `"auto"` / `true` —
  /// from half to double size.
  ({double lo, double hi, double? center})? _scaleRange(
      CallCtx c, Object? v, String what) {
    if (v == null || v == false || v == 1) return null;
    if (v == true || (v is String && v.toLowerCase() == 'auto')) {
      return (lo: 0.5, hi: 2.0, center: null);
    }
    num? lo, hi;
    if (v is RangeVal) {
      lo = v.lo;
      hi = v.hi;
    } else if (v is List && v.length == 2 && v[0] is num && v[1] is num) {
      lo = v[0] as num;
      hi = v[1] as num;
    } else if (v is num) {
      if (v <= 0) c.fail('$what: scale должен быть больше нуля');
      return (lo: v / 1.06, hi: v * 1.06, center: v.toDouble());
    }
    if (lo == null || hi == null) {
      c.fail('$what: scale — число (1.5), диапазон (0.5..2) или "auto"');
    }
    if (lo > hi) (lo, hi) = (hi, lo);
    if (lo <= 0) c.fail('$what: scale должен быть больше нуля');
    if (hi / lo > 16) c.fail('$what: слишком широкий диапазон scale');
    return (lo: lo.toDouble(), hi: hi.toDouble(), center: null);
  }

  Pt _scatter(CallCtx c, Pt p) {
    final off = _nOr(c, c.opt('offset') ?? c.opt('random_offset'), clickOffset, 'offset');
    if (off <= 0) return p;
    return (x: p.x + human.offset(off), y: p.y + human.offset(off));
  }

  String _fmtPt(Pt p) {
    final a = _area();
    final px = a.w > 0 ? ((p.x - a.x) * 100 / a.w).toStringAsFixed(1) : '?';
    final py = a.h > 0 ? ((p.y - a.y) * 100 / a.h).toStringAsFixed(1) : '?';
    return '${p.x}, ${p.y} ($px%, $py%)';
  }

  int _color(CallCtx c, Object? v) {
    if (v is num) return v.toInt() & 0xFFFFFF;
    if (v is String) {
      var h = v.trim().replaceFirst('#', '');
      if (h.length == 3) h = h.split('').map((ch) => '$ch$ch').join();
      final n = h.length == 6 ? int.tryParse(h, radix: 16) : null;
      if (n != null) return n;
    }
    c.fail('Цвет задаётся как "#RRGGBB", получено ${stringify(v, quote: true)}');
  }
}
