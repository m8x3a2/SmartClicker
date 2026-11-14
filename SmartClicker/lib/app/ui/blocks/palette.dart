// The list of blocks on the left: categories, search, samples to drag or click.
part of 'blocks_editor.dart';

extension _BlocksEditorStatePalette on _BlocksEditorState {
  Widget _palette(bool open) {
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => d.data.path != null && _editable,
      onAcceptWithDetails: (d) => _deletePath(d.data.path!),
      builder: (context, cand, _) => SizedBox(
        width: open ? _BlocksEditorState._railWidth + 1 + _BlocksEditorState._flyWidth : _BlocksEditorState._railWidth,
        child: Stack(
          children: [
            Row(
              children: [
                _rail(),
                if (open) const VerticalDivider(width: 1),
                if (open) Expanded(child: _flyout()),
              ],
            ),
            if (_dragging?.path != null)
              Positioned.fill(
                child: Container(
                  color: cand.isNotEmpty ? const Color(0xE0602025) : const Color(0xC0202228),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 34,
                        color: cand.isNotEmpty ? Colors.white : _muted,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        open ? 'Отпустите здесь,\nчтобы удалить блок' : 'Удалить',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cand.isNotEmpty ? Colors.white : _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rail() {
    final open = _floating ? _floatOpen : widget.palette;
    final searching = _search.text.trim().isNotEmpty;
    return Container(
      width: _BlocksEditorState._railWidth,
      color: _railBg,
      child: Column(
        children: [
          IconButton(
            tooltip: open ? 'Скрыть список блоков' : 'Показать список блоков',
            visualDensity: VisualDensity.compact,
            icon: Icon(open ? Icons.chevron_left : Icons.chevron_right, size: 20),
            onPressed: _togglePalette,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final c in blockCats)
                  InkWell(
                    onTap: () => _openCategory(c.id),
                    child: Tooltip(
                      message: c.title,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Color(c.color),
                                shape: BoxShape.circle,
                                border: _cat == c.id && open && !searching
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.short,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 10,
                                color: _cat == c.id && open && !searching ? Colors.white : _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _tools(),
        ],
      ),
    );
  }

  bool _matches(PaletteItem item, String q) {
    final shape = shapeOf(item.code);
    final spec = shape is XCall ? specFor(shape.name) : null;
    final hint =
        spec?.hint ?? (item.value ? '' : kindHints[_BlocksEditorState._snippet(item.code).firstOrNull?.kind] ?? '');
    return '${item.words} ${item.code} $hint'.toLowerCase().contains(q);
  }

  Widget _flyout() {
    final q = _search.text.trim().toLowerCase();
    final cat = catById(_cat);
    final items = q.isEmpty
        ? paletteFor(_cat, functions: _userFns)
        : [
            for (final c in blockCats)
              ...paletteFor(c.id, functions: _userFns).where((i) => _matches(i, q)),
          ];
    return Container(
      color: const Color(0xFF1B1D23),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _search,
                onChanged: (_) => _setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Найти блок…',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          onPressed: () => _setState(_search.clear),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
            child: Row(
              children: [
                if (q.isEmpty) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: Color(cat.color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    q.isEmpty ? cat.title : 'Найдено: ${items.length}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (q.isEmpty && _cat == 'funcs' && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Здесь появятся ваши функции. Создайте функцию блоком «функция» в «Управлении» — '
                'и её можно будет вызывать отсюда.',
                style: TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
              ),
            ),
          if (q.isEmpty && _cat == 'other')
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: OutlinedButton.icon(
                onPressed: _editable ? _insertCode : null,
                icon: const Icon(Icons.code, size: 16),
                label: const Text('Вставить код…'),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _paletteScroll,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
              itemCount: items.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Align(alignment: Alignment.centerLeft, child: _paletteItem(items[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _insertCode() async {
    final res = await _askCode(
      context,
      title: 'Вставить код',
      initial: '',
      multiline: true,
      validate: codeError,
    );
    if (res == null || res.trim().isEmpty || !mounted) return;
    _insertAtSelection(parseSnippet(res));
  }

  Widget _paletteItem(PaletteItem item) {
    final r = _R(this, edit: false, palette: true);
    final Widget view;
    if (item.value) {
      view = r.slot(item.code, id: '', spec: null, set: null);
    } else {
      final nodes = _BlocksEditorState._snippet(item.code);
      view = nodes.isEmpty ? Text(item.code) : r.stmt(nodes.first, const [0]);
    }
    final drag = _Drag.palette(item);
    return _HintRegion(
      ed: this,
      content: () => _paletteHint(item),
      child: Draggable<_Drag>(
        data: drag,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _feedback(view),
        onDragStarted: () => _dragStart(drag),
        onDragUpdate: (d) => _dragMove(d.globalPosition),
        onDragEnd: (_) => _dragEnd(),
        child: MouseRegion(
          cursor: _editable ? SystemMouseCursors.grab : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: () => _addFromPalette(item),
            child: AbsorbPointer(child: view),
          ),
        ),
      ),
    );
  }

  Widget _feedback(Widget view) => Transform.translate(
    offset: const Offset(10, 6),
    child: Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Opacity(opacity: 0.88, child: view),
      ),
    ),
  );
}
