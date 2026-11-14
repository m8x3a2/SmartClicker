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
      // Programs take typed letters with a lag: sent all at once, some of
      // them are lost (the Windows 11 Notepad loses most, and at 10 ms per
      // letter still one now and then; 20 ms is reliable there — checked by
      // tool/smoke_type.dart). The setting is 50 ms for a margin; delay: 0 —
      // all at once.
      final delay = _nOr(c, c.opt('delay'), humanMode ? math.max(70, typeDelay) : typeDelay, 'delay');
      final shown = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      if (!await _guardInput('ввод текста "$shown"')) return null;
      if (delay <= 0) {
        backend.typeText(text);
        _keysSent();
      } else {
        for (final ch in text.split('')) {
          backend.typeText(ch);
          _keysSent();
          await this.sleep(humanMode ? delay * (0.5 + rng.nextDouble()) : delay, jitter: false);
        }
      }
      return null;
    }, ['type_text', 'write']);

    _def('paste', (c) async {
      final text = stringify(c.arg(0, 'text'));
      final shown = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      if (!await _guardInput('вставка из буфера "$shown"')) return null;
      backend.setClipboard(text);
      await this.sleep(50, jitter: false);
      try {
        _key('ctrl', true);
        _key('v', true);
        await this.sleep(30, jitter: false);
      } finally {
        _key('v', false);
        _key('ctrl', false);
      }
      return null;
    });
  }
}
