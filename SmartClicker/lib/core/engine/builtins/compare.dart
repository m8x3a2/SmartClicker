// Built-in functions: comparing an area of the screen in place — with a
// saved picture or with a snapshot taken earlier (same, region_diff,
// snapshot, changed). Searching a picture anywhere is find_image.
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsCompare on ScriptRuntime {
  void _registerCompare() {
    // A picture of the area kept in memory: compare with it later.
    _def('snapshot', (c) {
      final r = _region(c, 0, 'snapshot');
      final id = ++_snapshotSeq;
      _snapshots[id] = (r: r, img: Bitmap(r.w, r.h, backend.capture(r.x, r.y, r.w, r.h)));
      // a loop taking snapshots must not eat the memory
      if (_snapshots.length > 100) _snapshots.remove(_snapshots.keys.first);
      final a = _area();
      return <String, Object?>{'snapshot': id, 'x': r.x - a.x, 'y': r.y - a.y, 'w': r.w, 'h': r.h};
    });

    // How much of the area differs, 0..100 %.
    _def('region_diff', (c) => (_compare(c, 'region_diff').share * 1000).round() / 10);

    // The area looks like the picture (or the snapshot): at most percent:
    // (2 by default) of its pixels differ by more than tolerance: (20).
    _def('same', (c) {
      final d = _compare(c, 'same');
      return d.share * 100 <= d.percent;
    });

    // The opposite of same: the area is no longer what the snapshot shows.
    _def('changed', (c) {
      final d = _compare(c, 'changed');
      return d.share * 100 > d.percent;
    });
  }

  /// The picture or snapshot of argument 0 against the screen now: where
  /// (x, y of arguments 1-2, or where the picture was cut from / the
  /// snapshot was taken) and the share of differing pixels.
  ({double share, num percent}) _compare(CallCtx c, String what) {
    final tol = _nOr(c, c.opt('tolerance'), 20, 'tolerance').round();
    final percent = _nOr(c, c.opt('percent'), 2, 'percent');
    final first = c.arg(0, 'picture');
    final a = _area();
    final n = c.args.length;
    if (n == 2 || n == 4 || n > 5) {
      c.fail('$what: после картинки — место x, y (или x, y, ширина, высота), например $what("кнопка", 820, 400)');
    }
    Bitmap img;
    Rect4 r;
    if (first is Map && first['snapshot'] is int) {
      final s = _snapshots[first['snapshot']];
      if (s == null) c.fail('$what: снимок устарел — сделайте его заново командой snapshot(...)');
      img = s.img;
      r = s.r;
    } else if (first is String) {
      img = _image(c, first, what);
      final o = n >= 3 ? null : _imageOrigin(first);
      if (n < 3 && o == null) {
        c.fail('$what: неизвестно, где была картинка "$first" (её вырезали не в SmartClicker или раньше) — '
            'укажите место: $what("$first", x, y)');
      }
      r = (x: o?.x ?? 0, y: o?.y ?? 0, w: img.w, h: img.h);
    } else {
      c.fail('$what: первый аргумент — имя картинки ("кнопка") или снимок из snapshot(...)');
    }
    if (n >= 3) {
      r = (x: _coord(c, c.arg(1), true, a, what), y: _coord(c, c.arg(2), false, a, what), w: r.w, h: r.h);
    }
    if (n == 5) {
      final w = _size(c, c.arg(3), true, a, what), h = _size(c, c.arg(4), false, a, what);
      if (w != img.w || h != img.h) {
        c.fail('$what: картинка ${img.w} × ${img.h} px, а область $w × $h — сравнивается область '
            'размером с картинку. Если картинка могла стать крупнее или мельче, ищите её: '
            'find_image("…", x, y, w, h, scale: "auto")');
      }
    }
    final now = backend.capture(r.x, r.y, r.w, r.h);
    return (share: pictureDiff(img.bgra, now, r.w, r.h, tolerance: tol), percent: percent);
  }

  /// Where the picture [name] was cut from (kept inside the PNG), or null.
  ({int x, int y, int w, int h})? _imageOrigin(String name) {
    final path = _imagePath(name);
    if (_imageOrigins.containsKey(path)) return _imageOrigins[path];
    try {
      return _imageOrigins[path] = pictureOrigin(File(path).readAsBytesSync());
    } catch (_) {
      return _imageOrigins[path] = null;
    }
  }
}
