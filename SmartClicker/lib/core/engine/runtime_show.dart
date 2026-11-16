// show("Убито", kills): values seen on the mini panel (and over the editor)
// while the script works; variables pinned in the «Переменные» tab are sent
// the same way twice a second.
part of 'runtime.dart';

/// At most this many values are shown at once (the mini panel is small).
const showLimit = 4;

extension _RuntimeShow on ScriptRuntime {
  void _registerShow() {
    // show("Убито", kills) — set or update; show("Убито") — remove.
    _def('show', (c) {
      final label = _s(c, c.arg(0, 'label'), 'show').trim();
      if (label.isEmpty) c.fail('show: подпись не может быть пустой — show("Убито", kills)');
      if (c.args.length < 2) {
        _showValue(label, null);
        return null;
      }
      if (!_shown.containsKey(label) && _shown.length >= showLimit) {
        c.fail('show: на панели помещается $showLimit значения — уберите лишнее: show("$label") без значения');
      }
      _showValue(label, stringify(c.arg(1)));
      return null;
    });
  }

  /// Sends a shown value when it changed; null — removes it.
  void _showValue(String label, String? text) {
    if (text == null) {
      if (_shown.remove(label) == null) return;
    } else {
      final v = text.length > 60 ? '${text.substring(0, 57)}…' : text;
      if (_shown[label] == v) return;
      _shown[label] = v;
    }
    emit({'t': 'show', 'k': label, 'v': _shown[label]});
  }

  /// Variables pinned in the «Переменные» tab: their current values (only
  /// variables of the script itself, not inside functions).
  void _sendPinned() {
    for (final name in pinnedVars) {
      final g = interp.globals;
      if (!g.vars.containsKey(name)) continue;
      _showValue(name, ScriptRuntime.preview(g.vars[name]));
    }
  }
}
