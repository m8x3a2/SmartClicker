// Built-in functions: keyboard (key, key_down, type, paste).
part of '../runtime.dart';

extension ScriptRuntimeBuiltinsKeyboard on ScriptRuntime {
  void _registerKeyboard() {
    _def('key', (c) async {
      final spec = _s(c, c.arg(0, 'key'), 'key');
      final keys = _combo(c, spec);
      final hold = _nOr(c, c.opt('hold'), humanMode ? 35 + rng.nextInt(60) : 20, 'hold');
      final count = _nOr(c, c.opt('count'), 1, 'count').round();
      if (!await _guardInput('клавиша $spec${count > 1 ? ' ×$count' : ''}')) return null;
      for (var i = 0; i < count; i++) {
        if (i > 0) await this.sleep(humanMode ? 60 + rng.nextInt(60) : 40, jitter: false);
        if (!_windowOk()) await _guardInput('восстановить окно для нажатия');
        try {
          for (final k in keys) {
            _key(k, true);
          }
          await this.sleep(hold, jitter: false);
        } finally {
          for (final k in keys.reversed) {
            _key(k, false);
          }
        }
      }
      return null;
    }, ['press']);

    _def('key_down', (c) async {
      final keys = _combo(c, _s(c, c.arg(0, 'key'), 'key_down'));
      if (!await _guardInput('зажать ${keys.join('+')}')) return null;
      for (final k in keys) {
        _key(k, true);
      }
      return null;
    });

    _def('key_up', (c) async {
      final keys = _combo(c, _s(c, c.arg(0, 'key'), 'key_up'));
      if (!await _guardInput('отпустить ${keys.join('+')}')) return null;
      for (final k in keys.reversed) {
        _key(k, false);
      }
      return null;
    });

    _def('type', (c) async {
      final text = stringify(c.arg(0, 'text'));
      final method = c.opt('method') == null ? typeMethod : _typeMethod(c, c.opt('method'));
      // Programs read typed letters with a lag: sent at once, some are lost
      // (Windows 11 Notepad). Safe layout characters go as real keys, one per
      // `delay` (setting, 50 ms); delay: 0 — all at once, as Unicode.
      var delay = _nOr(c, c.opt('delay'), humanMode ? math.max(70, typeDelay) : typeDelay, 'delay');
      // Real keys sent in a burst come out wrong (Shift not yet applied):
      // with method "keys" they always go one by one.
      if (method == TypeMethod.keys && delay < 10) delay = 10;
      final shown = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      final how = method == TypeMethod.auto ? '' : ' (${method.name})';
      if (!await _guardInput('ввод текста "$shown"$how')) return null;
      if (delay <= 0) {
        // All at once only as Unicode: real keys sent in a burst come out
        // wrong (Shift not yet applied: "мир1" for "мир!", checked in the
        // Windows 11 Notepad), Unicode letters are at worst lost.
        backend.typeText(text, method: TypeMethod.unicode);
        _keysSent(text.length);
      } else {
        for (final rune in text.runes) {
          if (!_windowOk()) {
            await _guardInput('восстановить окно для продолжения ввода');
          }
          final ch = String.fromCharCode(rune);
          backend.typeText(ch, method: method);
          _keysSent();
          await this.sleep(humanMode ? delay * (0.5 + rng.nextDouble()) : delay, jitter: false);
          // Text services may finish a word asynchronously at whitespace.
          // Keep the configured character pace, but let that boundary settle.
          if (ch.trim().isEmpty) await this.sleep(100, jitter: false);
        }
      }
      return null;
    }, ['type_text', 'write']);

    _def('paste', (c) async {
      final text = stringify(c.arg(0, 'text'));
      final shown = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      if (!await _guardInput('вставка из буфера "$shown"')) return null;
      final restore = c.opt('restore') == null || truthy(c.opt('restore'));
      // A paste right after another one: the user's text is still pending.
      final before = _clipRestore != null ? _clipBefore : _readClipboard();
      _cancelClipboardRestore();
      backend.setClipboard(text);
      await this.sleep(50, jitter: false);
      if (!_windowOk()) await _guardInput('восстановить окно для вставки');
      try {
        _key('ctrl', true);
        _key('v', true);
        await this.sleep(30, jitter: false);
      } finally {
        _key('v', false);
        _key('ctrl', false);
      }
      // Empty: nothing to give back (or a picture/files, which are gone anyway).
      if (restore && before != null && before.isNotEmpty && before != text) {
        _restoreClipboardLater(before);
      }
      return null;
    });
  }

  /// "auto" | "unicode" | "keys" of type(method:) and set_option.
  TypeMethod _typeMethod(CallCtx c, Object? v) {
    final name = '$v'.toLowerCase();
    for (final m in TypeMethod.values) {
      if (m.name == name) return m;
    }
    c.fail('type: method может быть "auto", "keys" или "unicode", а не "$v"');
  }

  String? _readClipboard() {
    try {
      return backend.getClipboard();
    } catch (_) {
      return null;
    }
  }

  /// Programs read the clipboard a moment after Ctrl+V: what the user had
  /// copied comes back after [_clipDelayMs].
  static const _clipDelayMs = 500;

  void _restoreClipboardLater(String before) {
    _clipBefore = before;
    _clipSw
      ..reset()
      ..start();
    _clipRestore = Timer(const Duration(milliseconds: _clipDelayMs), () {
      _clipRestore = null;
      try {
        backend.setClipboard(before);
      } catch (_) {}
    });
  }

  void _cancelClipboardRestore() {
    _clipRestore?.cancel();
    _clipRestore = null;
  }

  /// The script ends: wait out the rest of the delay and put it back now.
  Future<void> _restoreClipboardNow() async {
    if (_clipRestore == null) return;
    _cancelClipboardRestore();
    final left = _clipDelayMs - _clipSw.elapsedMilliseconds;
    if (left > 0) await Future<void>.delayed(Duration(milliseconds: left));
    try {
      backend.setClipboard(_clipBefore);
    } catch (_) {}
  }
}
