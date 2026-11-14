// Find and replace bar of the editor (Ctrl+F, Ctrl+H).
part of 'code_editor.dart';

extension _CodeEditorStateEditorSearch on _CodeEditorState {
  void _openFind({bool replace = false}) {
    _hideAssist();
    final c = widget.controller;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(c.text);
      if (!picked.contains('\n') && picked.length <= 200) _findCtrl.text = picked;
    }
    _setState(() {
      _findOpen = true;
      if (replace && !widget.viewer) _replaceOpen = true;
    });
    _findFocus.requestFocus();
    _findCtrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _findCtrl.text.length);
    _onQuery();
  }

  void _closeFind() {
    final code = _code;
    if (code != null) {
      code.query = '';
      code.activeMatch = -1;
    }
    _setState(() => _findOpen = false);
    _editorFocus.requestFocus();
  }

  void _onQuery() {
    final code = _code;
    if (code == null) return;
    _findInfo = '';
    code.query = _findCtrl.text;
    final found = code.matches;
    if (found.isEmpty) {
      code.activeMatch = -1;
    } else {
      // Start from the caret, like every editor does.
      final sel = widget.controller.selection;
      final from = sel.isValid ? sel.start : 0;
      final i = found.indexWhere((m) => m.start >= from);
      _goTo(i < 0 ? 0 : i);
    }
    _setState(() {});
  }

  void _goTo(int index) {
    final code = _code;
    if (code == null) return;
    final found = code.matches;
    if (found.isEmpty) return;
    final i = index % found.length;
    code.activeMatch = i;
    widget.controller.selection =
        TextSelection(baseOffset: found[i].start, extentOffset: found[i].end);
    _reveal(found[i].start, center: true);
    _setState(() {});
  }

  void _stepFind(int delta) {
    final code = _code;
    if (!_findOpen || code == null || code.matches.isEmpty) return;
    _findInfo = '';
    _goTo(code.activeMatch + delta);
  }

  void _replaceOne() {
    final code = _code;
    if (code == null || widget.readOnly || code.matches.isEmpty) return;
    final found = code.matches;
    final m = found[code.activeMatch.clamp(0, found.length - 1)];
    final to = _replaceCtrl.text;
    final after = m.start + to.length;
    widget.controller.value = TextEditingValue(
      text: widget.controller.text.replaceRange(m.start, m.end, to),
      selection: TextSelection.collapsed(offset: after),
    );
    final rest = code.matches;
    if (rest.isEmpty) {
      code.activeMatch = -1;
      _setState(() {});
    } else {
      final i = rest.indexWhere((r) => r.start >= after);
      _goTo(i < 0 ? 0 : i);
    }
  }

  void _replaceAll() {
    final code = _code;
    if (code == null || widget.readOnly || code.matches.isEmpty) return;
    final found = code.matches;
    final text = widget.controller.text;
    final to = _replaceCtrl.text;
    final out = StringBuffer();
    var pos = 0;
    for (final m in found) {
      out
        ..write(text.substring(pos, m.start))
        ..write(to);
      pos = m.end;
    }
    out.write(text.substring(pos));
    final count = found.length;
    widget.controller.value = TextEditingValue(
      text: out.toString(),
      selection: TextSelection.collapsed(
          offset: math.min(found.first.start + to.length, out.length)),
    );
    code.activeMatch = code.matches.isEmpty ? -1 : 0;
    _setState(() => _findInfo = 'заменено: $count');
  }

  Widget _findBar() {
    final code = _code;
    final total = code?.matches.length ?? 0;
    final label = _findInfo.isNotEmpty
        ? _findInfo
        : _findCtrl.text.isEmpty
            ? ''
            : total == 0
                ? 'не найдено'
                : '${(code!.activeMatch + 1).clamp(1, total)} из $total';

    InputDecoration deco(String hint) => InputDecoration(
          isDense: true,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        );
    Widget icon(IconData i, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(i, size: 18),
          tooltip: tip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          onPressed: onTap,
        );
    const fieldStyle = TextStyle(fontSize: 13.5);

    return Material(
      elevation: 8,
      color: const Color(0xFF2A2D36),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
                _stepFind(-1),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _findCtrl,
                      focusNode: _findFocus,
                      style: fieldStyle,
                      decoration:
                          deco(widget.viewer ? 'Поиск (Ctrl+F)' : 'Найти'),
                      onChanged: (_) => _onQuery(),
                      onEditingComplete: () {}, // keep the focus on Enter
                      onSubmitted: (_) => _stepFind(1),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: _muted)),
                  ),
                  icon(Icons.keyboard_arrow_up, 'Предыдущее (Shift+Enter)',
                      () => _stepFind(-1)),
                  icon(Icons.keyboard_arrow_down, 'Следующее (Enter)',
                      () => _stepFind(1)),
                  if (!widget.viewer)
                    icon(Icons.find_replace, 'Замена (Ctrl+H)',
                        () => _setState(() => _replaceOpen = !_replaceOpen)),
                  icon(Icons.close, 'Закрыть (Esc)', _closeFind),
                ],
              ),
              if (_replaceOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _replaceCtrl,
                          style: fieldStyle,
                          decoration: deco('Заменить на'),
                          onEditingComplete: () {},
                          onSubmitted: (_) => _replaceOne(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: widget.readOnly ? null : _replaceOne,
                        child: const Text('Заменить'),
                      ),
                      TextButton(
                        onPressed: widget.readOnly ? null : _replaceAll,
                        child: const Text('Заменить все'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
