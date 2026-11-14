// The canvas with the blocks: layout, error banner, end of the script, background.
part of 'blocks_editor.dart';

/// Faint dots on the background of the blocks.
class _Dots extends CustomPainter {
  const _Dots();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _canvasBg);
    final p = Paint()..color = const Color(0x14FFFFFF);
    for (var x = 12.0; x < size.width; x += 22) {
      for (var y = 12.0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

// ------------------------------------------------------------------- dialogs

extension _BlocksEditorStateCanvas on _BlocksEditorState {
  void _togglePalette() {
    if (_floating) {
      _setState(() => _floatOpen = !_floatOpen);
    } else {
      widget.onPalette?.call(!widget.palette);
    }
  }

  void _openCategory(String id) {
    final again = _cat == id && _search.text.isEmpty;
    _setState(() {
      _cat = id;
      _search.clear();
      if (_floating) _floatOpen = !(again && _floatOpen);
    });
    if (!_floating && !widget.palette) widget.onPalette?.call(true);
    if (_paletteScroll.hasClients) _paletteScroll.jumpTo(0);
  }

  Widget _errorBanner() => Container(
    margin: const EdgeInsets.all(8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: const Color(0xFF3A2A1E),
      border: Border.all(color: const Color(0xFF8A5A2E)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFE0A66A), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _doc == null
                ? 'В коде ошибка (строка $_errLine): $_error. Блоки появятся, когда её исправить.'
                : 'В коде сейчас ошибка (строка $_errLine): $_error. Блоки обновятся, когда код станет правильным.',
            style: const TextStyle(fontSize: 13, color: _text),
          ),
        ),
        if (widget.onShowCode != null)
          TextButton(
            onPressed: () => widget.onShowCode!(_errLine),
            child: const Text('Показать в коде'),
          ),
      ],
    ),
  );

  /// Undo, redo and the keys, at the bottom of the column of categories.
  Widget _tools() {
    Widget btn(IconData icon, String tip, VoidCallback? f) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: f,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 18, color: f == null ? const Color(0x55FFFFFF) : _text),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            btn(Icons.undo, 'Отменить (Ctrl+Z)', _undo.isEmpty || !_editable ? null : _undoAct),
            btn(Icons.redo, 'Вернуть (Ctrl+Y)', _redo.isEmpty || !_editable ? null : _redoAct),
          ],
        ),
        const Tooltip(
          message:
              'Блоки перетаскивают мышью за название; щелчок по блоку в списке '
              'добавляет его после выделенного.\n'
              'Del — удалить, Ctrl+D — копия, Ctrl+C / Ctrl+X / Ctrl+V — через буфер,\n'
              'Alt+↑ / Alt+↓ — передвинуть, ↑ / ↓ — выбрать соседний, правая кнопка — меню.\n'
              'Блок можно бросить на список блоков — он удалится.',
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Icon(Icons.help_outline, size: 18, color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _canvas() {
    final doc = _doc;
    final nodes = doc?.nodes ?? const <BNode>[];
    final r = _R(this, edit: _editable);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _select(null);
          _lastSlot = null;
          if (_floatOpen) _setState(() => _floatOpen = false);
          _focus.requestFocus();
        },
        child: CustomPaint(
          painter: const _Dots(),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: _canvasKey,
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(14, _error != null ? 64 : 14, 14, 60),
              child: Opacity(
                opacity: _error != null ? 0.45 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < nodes.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : 5.0 + 10 * nodes[i].blank.clamp(0, 2),
                        ),
                        child: r.stmt(nodes[i], [i]),
                      ),
                    _endZone(nodes.length),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endZone(int count) {
    final empty = count == 0;
    return _Drop(
      ed: this,
      after: _Pos(null, 0, count),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: BoxConstraints(minHeight: empty ? 200 : 90, minWidth: 260),
        alignment: empty ? Alignment.center : Alignment.topLeft,
        child: empty
            ? Text(
                _error != null && _doc == null ? '' : 'Перетащите сюда блоки из списка слева\nили щёлкните по блоку — он добавится в конец',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.5),
              )
            : _dragging != null
            ? const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text('в конец скрипта', style: TextStyle(color: _muted, fontSize: 12)),
              )
            : null,
      ),
    );
  }
}
