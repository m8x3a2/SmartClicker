// Where lines are on screen: with wrapping a long line takes several rows,
// so numbers, markers, hints and scrolling ask the text field itself.
part of 'code_editor.dart';

/// Mark in the line numbers for the rows a wrapped line continues on.
const wrapMark = '↪';

extension _EditorLayout on _CodeEditorState {
  /// The text box inside the TextField (null before the first layout).
  RenderEditable? get _editable {
    final s = _fieldKey.currentState;
    if (s is! TextSelectionGestureDetectorBuilderDelegate) return null;
    final ed = (s as TextSelectionGestureDetectorBuilderDelegate)
        .editableTextKey
        .currentState
        ?.renderEditable;
    return ed != null && ed.attached && ed.hasSize ? ed : null;
  }

  /// First screen row of every line (0-based) plus the number of rows at
  /// the end; null — one row per line (no wrapping).
  List<int>? get _rows => _layout.value;

  /// Screen row where line [line0] (0-based) starts.
  int _rowOf(int line0) {
    final r = _rows;
    if (r == null) return line0;
    return r[line0.clamp(0, r.length - 1)];
  }

  /// Number of screen rows of line [line0].
  int _rowsIn(int line0) {
    final r = _rows;
    if (r == null || line0 + 1 >= r.length) return 1;
    return math.max(1, r[line0 + 1] - r[line0]);
  }

  /// Line (0-based) shown on screen row [row].
  int _lineAtRow(int row) {
    final r = _rows;
    if (r == null) return row;
    var lo = 0, hi = r.length - 2;
    if (hi < 0) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (r[mid] <= row) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Screen row of the caret placed at [offset].
  int _rowAtOffset(int offset) {
    final ed = _editable;
    if (_rows == null || ed == null) return _lineCol(offset).line;
    final o = offset.clamp(0, widget.controller.text.length);
    final rect = ed.getLocalRectForCaret(TextPosition(offset: o));
    return (rect.center.dy / _lineHeight).floor();
  }

  /// Left edge of the caret at [offset] in the text box.
  double _xAtOffset(int offset) {
    final ed = _editable;
    if (_rows == null || ed == null) return _lineCol(offset).col * _charW;
    final o = offset.clamp(0, widget.controller.text.length);
    return ed.getLocalRectForCaret(TextPosition(offset: o)).left;
  }

  /// Text offset of the character under the mouse (null: not over text).
  int? _charAtPoint(Offset global, Offset local) {
    final text = widget.controller.text;
    if (_rows == null) {
      final lineNo = (local.dy / _lineHeight).floor();
      final col = (local.dx / _charW).floor();
      if (lineNo < 0 || col < 0) return null;
      var offset = 0;
      for (var i = 0; i < lineNo; i++) {
        final nl = text.indexOf('\n', offset);
        if (nl < 0) return null;
        offset = nl + 1;
      }
      final end = text.indexOf('\n', offset);
      final len = (end < 0 ? text.length : end) - offset;
      return col < len ? offset + col : null;
    }
    final ed = _editable;
    if (ed == null) return null;
    final p = ed.globalToLocal(global);
    if (p.dy < 0 || p.dy >= ed.size.height) return null;
    final pos = ed.getPositionForPoint(global);
    var o = pos.offset;
    // The nearest caret may be right of the character under the mouse.
    if (o > 0 && p.dx < ed.getLocalRectForCaret(pos).left) o--;
    if (o >= text.length || text[o] == '\n') return null;
    return o;
  }

  /// Asks the text field where every line starts (after a layout).
  void _measure() {
    if (!mounted) return;
    if (!widget.wrap) {
      if (_layout.value != null) _layout.value = null;
      return;
    }
    final ed = _editable;
    if (ed == null) return;
    final text = widget.controller.text;
    final rows = <int>[];
    var start = 0;
    while (true) {
      final rect = ed.getLocalRectForCaret(TextPosition(offset: start));
      rows.add((rect.center.dy / _lineHeight).floor());
      final nl = text.indexOf('\n', start);
      if (nl < 0) break;
      start = nl + 1;
    }
    rows.add(math.max(rows.last + 1, (ed.size.height / _lineHeight).round()));
    if (!listEquals(rows, _layout.value)) _layout.value = rows;
  }

  void _measureLater() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      _measure();
    });
  }

  /// Width of the longest line (no wrapping: the width of the text).
  void _measureWidth() {
    final text = widget.controller.text;
    var best = '';
    var start = 0;
    while (start <= text.length) {
      var nl = text.indexOf('\n', start);
      if (nl < 0) nl = text.length;
      if (nl - start > best.length) best = text.substring(start, nl);
      start = nl + 1;
    }
    if (best == _longest) return;
    _longest = best;
    final p = TextPainter(
      text: TextSpan(text: best, style: _fieldStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _textWidth = p.width;
    p.dispose();
  }

  /// The numbers column text: a number for every line and [wrapMark] for
  /// the rows it continues on.
  String _gutterText(int n) {
    final b = StringBuffer();
    for (var i = 0; i < n; i++) {
      if (i > 0) b.write('\n');
      b.write(i + 1);
      for (var k = 1; k < _rowsIn(i); k++) {
        b.write('\n$wrapMark');
      }
    }
    return b.toString();
  }
}
