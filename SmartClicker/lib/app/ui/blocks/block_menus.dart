// Right-click menus of blocks and slots, "edit as code" dialog.
part of 'blocks_editor.dart';

/// Asks for code; [validate] returns an error message or null.
Future<String?> _askCode(
  BuildContext context, {
  required String title,
  required String initial,
  required String? Function(String) validate,
  bool multiline = false,
}) {
  final c = TextEditingController(text: initial);
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          final e = validate(c.text);
          if (e != null) {
            setLocal(() => err = e);
            return;
          }
          Navigator.pop(ctx, c.text);
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: multiline ? 560 : 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  autofocus: true,
                  minLines: multiline ? 4 : 1,
                  maxLines: multiline ? 14 : 1,
                  style: _mono.copyWith(color: _text, fontSize: 13.5),
                  onSubmitted: multiline ? null : (_) => submit(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: err,
                    errorMaxLines: 3,
                    helperText: multiline
                        ? 'Код на языке скриптов; знакомые команды станут блоками'
                        : 'Выражение: 50%, "текст", x + 1, pixel(10, 20), pos.x…',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(onPressed: submit, child: const Text('Применить')),
          ],
        );
      },
    ),
  );
}

extension _BlocksEditorStateBlockMenus on _BlocksEditorState {
  Future<T?> _menu<T>(Offset at, List<PopupMenuEntry<T>> items) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }

  PopupMenuItem<String> _item(String value, String text, {String? keys, bool enabled = true}) =>
      PopupMenuItem(
        value: value,
        enabled: enabled,
        height: 36,
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
            if (keys != null)
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(keys, style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ],
        ),
      );

  Future<void> _blockMenu(BNode n, List<int> path, Offset at) async {
    _select(path);
    final edit = _editable;
    final bp = widget.breakpoints?.value.contains(n.line) ?? false;
    final v = await _menu<String>(at, [
      _item('dup', 'Дублировать', keys: 'Ctrl+D', enabled: edit),
      _item('copy', 'Копировать код', keys: 'Ctrl+C'),
      _item('cut', 'Вырезать', keys: 'Ctrl+X', enabled: edit),
      _item('paste', 'Вставить после', keys: 'Ctrl+V', enabled: edit),
      const PopupMenuDivider(),
      if (n.kind == BK.ifs) ...[
        _item('elseif', 'Добавить «иначе если»', enabled: edit),
        if (!n.hasElse) _item('else', 'Добавить «иначе»', enabled: edit),
        if (n.hasElse) _item('noelse', 'Убрать «иначе» (с блоками внутри)', enabled: edit),
      ],
      if (n.kind == BK.repeat)
        n.args.isEmpty
            ? _item('count', 'Повторить N раз', enabled: edit)
            : _item('forever', 'Повторять всегда', enabled: edit),
      if (n.kind == BK.ret)
        n.args.isEmpty
            ? _item('retval', 'Вернуть значение', enabled: edit)
            : _item('noretval', 'Без значения', enabled: edit),
      if (n.kind == BK.tryc)
        n.hasFinally
            ? _item('nofinally', 'Убрать «в конце»', enabled: edit)
            : _item('finally', 'Добавить «в конце»', enabled: edit),
      _item('note', 'Добавить комментарий выше', enabled: edit),
      _item('code', 'Изменить как код…', enabled: edit),
      if (widget.onBreakpoint != null && n.line > 0)
        _item('break', bp ? 'Убрать точку останова' : 'Поставить точку останова'),
      const PopupMenuDivider(),
      _item('delete', 'Удалить', keys: 'Del', enabled: edit),
    ]);
    if (!mounted || v == null) return;
    switch (v) {
      case 'dup':
        _duplicate(path);
      case 'copy':
        _copy(n);
      case 'cut':
        _copy(n, cut: true);
      case 'paste':
        await _paste();
      case 'elseif':
        _change(path, (x) {
          x.args.add('true');
          x.bodies.insert(x.args.length - 1, []);
        });
      case 'else':
        _change(path, (x) => x.bodies.add([]));
      case 'noelse':
        _change(path, (x) => x.bodies.removeLast());
      case 'count':
        _change(path, (x) => x.args.add('10'));
      case 'forever':
        _change(path, (x) => x.args.clear());
      case 'retval':
        _change(path, (x) => x.args.add('0'));
      case 'noretval':
        _change(path, (x) => x.args.clear());
      case 'finally':
        _change(path, (x) {
          x.extra = '${x.extra}f';
          x.bodies.add([]);
        });
      case 'nofinally':
        _change(path, (x) {
          x.extra = x.extra.replaceAll('f', '');
          x.bodies.removeLast();
        });
      case 'note':
        final note = BNode(BK.comment, text: ' Комментарий');
        _apply((d) {
          final x = d.resolve(path);
          if (x == null) return;
          final (owner, body, index) = _where(d, x);
          d.insert(owner, body, index, [note]);
        }, select: (_) => note);
      case 'code':
        await _editAsCode(path);
      case 'break':
        widget.onBreakpoint?.call(n.line);
      case 'delete':
        _deletePath(path);
    }
  }

  Future<void> _editAsCode(List<int> path) async {
    final doc = _doc;
    final n = doc?.resolve(path);
    if (doc == null || n == null) return;
    final res = await _askCode(
      context,
      title: 'Код блока',
      initial: generateNodes([n], unit: doc.unit),
      multiline: true,
      validate: (s) => s.trim().isEmpty ? null : codeError(s),
    );
    if (res == null || !mounted) return;
    List<BNode> nodes = const [];
    _apply((d) {
      final x = d.resolve(path);
      if (x == null) return;
      final (owner, body, index) = _where(d, x);
      d.remove(x);
      nodes = res.trim().isEmpty ? const [] : parseSnippet(res);
      d.insert(owner, body, index, nodes);
    }, select: (_) => nodes.firstOrNull);
  }

  Future<void> _slotMenu(
    Offset at,
    String src,
    PSpec? spec,
    ValueChanged<String> set,
    VoidCallback? remove,
  ) async {
    final vars = _doc == null ? const <String>[] : variableNames(_doc!);
    final v = await _menu<String>(at, [
      _item('code', 'Изменить как код…'),
      if (spec != null && spec.def != src) _item('def', 'Вернуть как было: ${spec.def}'),
      if (vars.isNotEmpty) const PopupMenuDivider(),
      for (final name in vars.take(12)) _item('var:$name', 'Переменная $name'),
      if (remove != null) ...[const PopupMenuDivider(), _item('remove', 'Убрать параметр')],
    ]);
    if (!mounted || v == null) return;
    if (v == 'code') {
      final res = await _askCode(
        context,
        title: spec == null ? 'Значение' : (spec.label.isNotEmpty ? spec.label : spec.name),
        initial: src,
        validate: exprError,
      );
      if (res != null) set(res.trim());
    } else if (v == 'def') {
      set(spec!.def);
    } else if (v.startsWith('var:')) {
      set(v.substring(4));
    } else if (v == 'remove') {
      remove!();
    }
  }
}
