// Draws comments and "code as is" blocks.
part of '../blocks_editor.dart';

extension _RenderNoteRender on _R {
  Widget _comment(BNode n, List<int> path) {
    final text = n.extra == 'block'
        ? n.text.trim()
        : n.text.split('\n').map((l) => l.startsWith(' ') ? l.substring(1) : l).join('\n');
    final box = Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3B3725),
        border: Border.all(color: const Color(0xFF5E5634)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          grab(n, path, const Icon(Icons.drag_indicator, size: 15, color: Color(0x88E8D98A))),
          const SizedBox(width: 2),
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.sticky_note_2_outlined, size: 15, color: Color(0xFFBFB27A)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: live
                ? _TextArea(
                    key: ValueKey('c${path.join('.')}'),
                    ed: ed,
                    id: '${path.join('.')}/text',
                    text: text,
                    style: const TextStyle(
                      color: Color(0xFFE8D98A),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                    live: true,
                    onCommit: (v) => ed._setField(
                      path,
                      'text',
                      v.split('\n').map((l) => l.isEmpty ? '' : ' $l').join('\n'),
                    ),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      color: Color(0xFFE8D98A),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
          ),
        ],
      ),
    );
    return _drop(path, _before(path), _after(path), _frame(n, path, box, BorderRadius.circular(6)));
  }

  Widget _code(BNode n, List<int> path) {
    final box = Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF22252D),
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          grab(n, path, const Icon(Icons.drag_indicator, size: 15, color: _muted)),
          const SizedBox(width: 2),
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text('код', style: TextStyle(color: _muted, fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: live
                ? _TextArea(
                    key: ValueKey('k${path.join('.')}'),
                    ed: ed,
                    id: '${path.join('.')}/code',
                    text: n.text,
                    style: _mono.copyWith(color: _text),
                    live: false,
                    validate: (s) => s.trim().isEmpty ? null : codeError(s),
                    onCommit: (v) {
                      if (v.trim().isEmpty) {
                        ed._deletePath(path);
                      } else {
                        ed._setField(path, 'text', v);
                      }
                    },
                  )
                : Text(n.text, style: _mono.copyWith(color: _text)),
          ),
          if (n.tail != null) ...[const SizedBox(width: 6), _tail(n.tail!)],
          if (!palette && n.line > 0) ...[const SizedBox(width: 6), _line(n)],
        ],
      ),
    );
    return _drop(path, _before(path), _after(path), _frame(n, path, box, BorderRadius.circular(6)));
  }

  /// Selection, run marks, menu and explanation around a comment or code block.
  Widget _frame(BNode n, List<int> path, Widget box, BorderRadius radius) {
    if (palette) return box;
    return _HintRegion(
      ed: ed,
      content: () => ed._blockHint(n),
      child: Listener(
        onPointerDown: (e) => ed._onRightClick(e, (at) => ed._blockMenu(n, path, at)),
        child: GestureDetector(
          onTap: () {
            ed._select(path);
            ed._lastSlot = null;
          },
          child: ListenableBuilder(
            listenable: ed._marks,
            builder: (context, child) {
              final run = identical(ed._runNode.value, n);
              final err = identical(ed._errNode.value, n);
              final sel = listEquals(ed._sel, path);
              final ring = err
                  ? const Color(0xFFFF5A5F)
                  : run
                  ? Colors.white
                  : sel
                  ? _accent
                  : null;
              return DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: ring == null ? null : Border.all(color: ring, width: 2),
                ),
                child: child,
              );
            },
            child: box,
          ),
        ),
      ),
    );
  }

  Widget _nameField(
    BNode n,
    List<int> path,
    String field,
    String value,
    bool Function(String) valid, {
    required _Look look,
    String placeholder = '',
  }) {
    final id = '${path.join('.')}/$field';
    if (!live) return _chip(value.isEmpty ? placeholder : value, look);
    return _SlotField(
      key: ValueKey(id),
      ed: ed,
      id: id,
      src: value,
      textMode: false,
      look: look,
      placeholder: placeholder,
      validate: valid,
      onChanged: (v) => ed._setField(path, field, v.trim()),
    );
  }
}
