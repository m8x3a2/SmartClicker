// Undo / redo of one script (Ctrl+Z, Ctrl+Y): every script keeps its own
// history while the program is open, so switching scripts loses nothing.

import 'package:flutter/services.dart' show TextEditingValue;

class EditHistory {
  EditHistory({this.limit = 300, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int limit;
  final DateTime Function() _clock;
  final List<TextEditingValue> _states = [];
  int _at = -1;
  DateTime? _lastTyping;

  /// Typing that comes this quickly after the previous letter is one step.
  static const _group = Duration(milliseconds: 1000);

  bool get canUndo => _at > 0;
  bool get canRedo => _at >= 0 && _at < _states.length - 1;
  int get length => _states.length;

  /// The text of the editor changed (or only the cursor moved).
  void record(TextEditingValue v) {
    if (_at < 0) {
      _states.add(v);
      _at = 0;
      return;
    }
    final top = _states[_at];
    if (top.text == v.text) {
      _states[_at] = v; // the cursor moved: remember where it is
      return;
    }
    // A new edit after undo drops the steps that could be redone.
    if (_at < _states.length - 1) _states.removeRange(_at + 1, _states.length);
    final now = _clock();
    final typing = _isTyping(top.text, v.text);
    final merge = typing &&
        _lastTyping != null &&
        now.difference(_lastTyping!) < _group && // the top step is typing too
        _at > 0;
    _lastTyping = typing ? now : null;
    if (merge) {
      _states[_at] = v;
    } else {
      _states.add(v);
      _at++;
      if (_states.length > limit) {
        _states.removeAt(0);
        _at--;
      }
    }
  }

  /// One letter typed or erased, not a new line: such steps are glued.
  static bool _isTyping(String a, String b) {
    if ((a.length - b.length).abs() != 1) return false;
    return b.length < a.length || _added(a, b) != '\n';
  }

  static String _added(String a, String b) {
    var i = 0;
    while (i < a.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return b.substring(i, i + 1);
  }

  /// The text to show after Ctrl+Z, or null if there is nothing to undo.
  TextEditingValue? undo() {
    if (!canUndo) return null;
    _lastTyping = null;
    return _states[--_at];
  }

  /// The text to show after Ctrl+Y, or null if there is nothing to redo.
  TextEditingValue? redo() {
    if (!canRedo) return null;
    _lastTyping = null;
    return _states[++_at];
  }
}
