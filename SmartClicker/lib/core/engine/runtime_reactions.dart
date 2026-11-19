// Reactions: a piece of code that runs by itself when something happens —
// a key is pressed (on_key), time has passed (every), a picture appeared
// (on_image), an area changed (watch) — while the main code waits. Checked between statements and
// during waits (wait, wait_until, wait_image…), never in the middle of an
// action; one reaction at a time, none inside another.
part of 'runtime.dart';

class _Reaction {
  final int id;
  final String kind; // 'key' | 'every' | 'image' | 'watch'
  final String what; // for the log: "f5", "5 мин", "враг"
  final Object? fn;
  final int line;

  // on_key: the keys of the combo and whether they were down last time.
  final List<int> keys;
  bool wasDown = false;

  // every / on_image: how often and when next.
  final int periodMs;
  int dueMs;

  // on_image: arguments for the search and whether it was seen last time.
  final List<Object?> imageArgs;
  final Map<String, Object?> imageNamed;
  bool seen = false;

  // watch: the rule, its options and what it remembers; pauseMs — rest
  // after the reaction ran.
  final WatchRule? rule;
  final WatchState watch = WatchState();
  final int tolerance, pauseMs;
  final num percent;
  final String mode;

  _Reaction(this.id, this.kind, this.what, this.fn, this.line,
      {this.keys = const [],
      this.periodMs = 0,
      this.dueMs = 0,
      this.imageArgs = const [],
      this.imageNamed = const {},
      this.rule,
      this.tolerance = 20,
      this.percent = 2,
      this.mode = 'median',
      this.pauseMs = 0});
}

extension ScriptRuntimeReactions on ScriptRuntime {
  void _registerReactions() {
    // on_key("f5", () => {…}) — the user pressed the key (or combo).
    _def('on_key', (c) {
      final spec = _s(c, c.arg(0, 'key'), 'on_key');
      final fn = _reactionFn(c, 'on_key');
      final vks = [for (final k in _combo(c, spec)) vkByName[k] ?? 0];
      final r = _Reaction(++_reactionIds, 'key', spec, fn, c.line, keys: vks);
      r.wasDown = vks.every(backend.isUserKeyDown); // a held key is not a press
      _reactions.add(r);
      return r.id;
    });

    // every(5m, () => {…}) — every so often (first time after the period).
    _def('every', (c) {
      final ms = _n(c, c.arg(0, 'ms'), 'every').round();
      if (ms < 100) c.fail('every: слишком часто — не меньше 100 мс');
      final fn = _reactionFn(c, 'every');
      final r = _Reaction(++_reactionIds, 'every', _msText(ms), fn, c.line,
          periodMs: ms, dueMs: _total.elapsedMilliseconds + ms);
      _reactions.add(r);
      return r.id;
    });

    // on_image("связь_потеряна", (pos) => {…}) — the picture appeared on the
    // screen (once per appearance); area: [x, y, w, h], interval: 1s.
    _def('on_image', (c) {
      final name = c.arg(0, 'name');
      _s(c, name, 'on_image');
      final fn = _reactionFn(c, 'on_image');
      final area = c.opt('area');
      final args = <Object?>[name];
      if (area is List) {
        if (area.length != 4) c.fail('on_image: area — четыре числа [x, y, w, h]');
        args.addAll(area);
      }
      final named = {
        for (final e in c.named.entries)
          if (!const {'area', 'interval'}.contains(e.key)) e.key: e.value
      };
      final every = _nOr(c, c.opt('interval'), 1000, 'interval').round().clamp(100, 3600000);
      final r = _Reaction(++_reactionIds, 'image', '$name', fn, c.line,
          periodMs: every, dueMs: 0, imageArgs: args, imageNamed: named);
      _reactions.add(r);
      return r.id;
    });

    // watch(x, y, w, h, () => {…}, when: "изменилась", every: 1s, pause: 0)
    // — the area changed / became a colour / brighter / darker / still.
    _def('watch', (c) {
      final at = c.args.indexWhere((a) => a is UserFn);
      final f = at >= 0 ? c.args[at] : c.opt('do');
      if (f is! UserFn) {
        c.fail('watch: нужна функция — watch(x, y, w, h, () => { … }, when: "изменилась")');
      }
      final area = at >= 0 ? c.args.sublist(0, at) : c.args;
      if (area.isNotEmpty && area.length != 4) {
        c.fail('watch: область задаётся четырьмя числами — x, y, ширина, высота (без области — весь экран)');
      }
      _region(CallCtx(area, const {}, c.line), 0, 'watch'); // checked now, not in the middle of the run
      final whenText = c.opt('when');
      final rule = parseWatchRule(whenText == null ? '' : _s(c, whenText, 'when'));
      if (rule == null) {
        c.fail('watch: when — "изменилась", "#FF0000" (стала цветом), "светлее 120", "темнее 80" '
            'или "не меняется 10s"');
      }
      final every = _nOr(c, c.opt('every'), 1000, 'every').round().clamp(100, 86400000);
      final r = _Reaction(++_reactionIds, 'watch', '$rule', f, c.line,
          periodMs: every,
          dueMs: 0,
          imageArgs: area,
          rule: rule,
          tolerance: _nOr(c, c.opt('tolerance'), 20, 'tolerance').round(),
          percent: _nOr(c, c.opt('percent'), 2, 'percent'),
          mode: _colorMode(c, 'median', 'watch'),
          pauseMs: math.max(0, _nOr(c, c.opt('pause'), 0, 'pause').round()));
      _reactions.add(r);
      return r.id;
    });

    // off(id) — this reaction no more; off() — none.
    _def('off', (c) {
      if (c.args.isEmpty) {
        _reactions.clear();
      } else {
        final id = _n(c, c.arg(0), 'off').round();
        _reactions.removeWhere((r) => r.id == id);
      }
      return null;
    });
  }

  Object? _reactionFn(CallCtx c, String fn) {
    final f = c.arg(1, 'do');
    if (f is! UserFn) {
      c.fail('$fn: вторым аргументом нужна функция: $fn(…, () => { … })');
    }
    return f;
  }

  static String _msText(int ms) {
    if (ms % 60000 == 0) return '${ms ~/ 60000} мин';
    if (ms % 1000 == 0) return '${ms ~/ 1000} с';
    return '$ms мс';
  }

  /// Runs what is due. Called between statements and during waits.
  Future<void> _reactionsTick() async {
    if (_inReaction || _reactions.isEmpty) return;
    final now = _total.elapsedMilliseconds;
    for (final r in [..._reactions]) {
      if (!_reactions.contains(r)) continue; // off() inside another one
      Object? arg;
      var fire = false;
      switch (r.kind) {
        case 'key':
          final down = r.keys.isNotEmpty && r.keys.every(backend.isUserKeyDown);
          fire = down && !r.wasDown;
          r.wasDown = down;
        case 'every':
          if (now >= r.dueMs) {
            fire = true;
            r.dueMs = now + r.periodMs;
          }
        case 'image':
          if (now >= r.dueMs) {
            r.dueMs = now + r.periodMs;
            final hit = _findImage(CallCtx(r.imageArgs, r.imageNamed, r.line), 1, 'on_image');
            fire = hit != null && !r.seen;
            r.seen = hit != null;
            arg = hit;
          }
        case 'watch':
          if (now >= r.dueMs) {
            r.dueMs = now + r.periodMs;
            final a = _region(CallCtx(r.imageArgs, const {}, r.line), 0, 'watch');
            final shot = backend.capture(a.x, a.y, a.w, a.h);
            // a window of another size: start watching it anew
            if (r.watch.ref != null && r.watch.ref!.length != shot.length) r.watch.ref = null;
            if (r.watch.prev != null && r.watch.prev!.length != shot.length) r.watch.prev = null;
            fire = watchStep(r.rule!, r.watch, shot, a.w, a.h, now,
                tolerance: r.tolerance, percent: r.percent, mode: r.mode);
            final color = r.watch.lastColor;
            arg = <String, Object?>{
              'color': ScriptRuntime.hex(color),
              'brightness': brightnessOf(color),
              'hue': hueOf(color),
            };
          }
      }
      if (!fire) continue;
      final word = switch (r.kind) {
        'key' => 'клавиша',
        'every' => 'каждые',
        'watch' => 'область',
        _ => 'картинка',
      };
      log('⚡ Реакция ($word ${r.what})');
      _inReaction = true;
      final line = _line;
      try {
        await interp.callFunction(r.fn, [?arg], const {}, r.line);
      } finally {
        _inReaction = false;
        _line = line;
        // The next time counts from the end: a reaction longer than its
        // period must not leave the main code without a turn.
        if (r.kind != 'key') r.dueMs = _total.elapsedMilliseconds + math.max(r.periodMs, r.pauseMs);
      }
    }
  }
}
