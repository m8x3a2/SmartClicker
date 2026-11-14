// Explanations under the mouse: texts for blocks, slots and samples, and the
// overlay that shows them.
part of 'blocks_editor.dart';

/// Explanation under the mouse: the innermost hovered part wins.
class _HintRegion extends StatelessWidget {
  final _BlocksEditorState ed;
  final InlineSpan Function() content;
  final Widget child;
  const _HintRegion({required this.ed, required this.content, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!ed.widget.hints) return child;
    return MouseRegion(
      onEnter: (_) => ed._hints.enter(context, content),
      onExit: (_) => ed._hints.exit(context),
      child: child,
    );
  }
}

class _Hints {
  final _BlocksEditorState ed;
  _Hints(this.ed);

  final _stack = <(BuildContext, InlineSpan Function())>[];
  Timer? _timer;
  OverlayEntry? _entry;

  void enter(BuildContext ctx, InlineSpan Function() content) {
    _stack.removeWhere((e) => identical(e.$1, ctx) || !e.$1.mounted);
    _stack.add((ctx, content));
    _schedule();
  }

  void exit(BuildContext ctx) {
    final top = _stack.isEmpty ? null : _stack.last.$1;
    _stack.removeWhere((e) => identical(e.$1, ctx) || !e.$1.mounted);
    if (identical(top, ctx)) _schedule();
  }

  void _schedule() {
    _hide();
    _timer?.cancel();
    if (_stack.isEmpty || ed._dragging != null) return;
    _timer = Timer(const Duration(milliseconds: 550), _show);
  }

  void _show() {
    _stack.removeWhere((e) => !e.$1.mounted);
    if (_stack.isEmpty || ed._dragging != null || !ed.mounted) return;
    final (ctx, content) = _stack.last;
    final box = ctx.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(ctx);
    final obox = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || overlay == null || obox == null) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: obox) & box.size;
    final span = content();
    _entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: _HintLayout(rect),
            child: Material(
              color: _cardBg,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Text.rich(
                  span,
                  style: const TextStyle(fontSize: 12.5, color: _text, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void hideAll() {
    _timer?.cancel();
    _hide();
  }
}

class _HintLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  _HintLayout(this.anchor);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(
    maxWidth: math.max(120, math.min(400, c.maxWidth - 16)),
    maxHeight: math.max(60, c.maxHeight - 16),
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = anchor.left.clamp(8.0, math.max(8.0, size.width - child.width - 8)).toDouble();
    var y = anchor.bottom + 6;
    if (y + child.height > size.height - 8) y = anchor.top - 6 - child.height;
    if (y < 8) y = 8;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_HintLayout old) => old.anchor != anchor;
}

class _Picture extends StatelessWidget {
  final String path;
  final String name;
  const _Picture({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    if (!f.existsSync()) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Картинки «$name» нет в папке files',
          style: const TextStyle(fontSize: 12, color: Color(0xFFFF7B72)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 160),
        child: Image.file(f, filterQuality: FilterQuality.none, fit: BoxFit.contain),
      ),
    );
  }
}

extension _BlocksEditorStateHints on _BlocksEditorState {
  InlineSpan _fnHint(FSpec f, {String? code}) => TextSpan(
    children: [
      TextSpan(text: '${f.label.replaceAll(RegExp(r'\s*\{\w+\}'), '')}\n', style: _BlocksEditorState._hTitle),
      TextSpan(text: f.hint),
      if (f.returns != null) TextSpan(text: '\nРезультат: ${f.returns}', style: _BlocksEditorState._hMuted),
      TextSpan(text: '\n${code ?? f.signature}', style: _BlocksEditorState._hCode),
    ],
  );

  InlineSpan _blockHint(BNode n) => n.tail == null
      ? _blockHintBody(n)
      : TextSpan(
          children: [
            _blockHintBody(n),
            TextSpan(text: '\nКомментарий: ${tailText(n.tail!)}', style: _BlocksEditorState._hMuted),
          ],
        );

  InlineSpan _blockHintBody(BNode n) {
    final code = n.src ?? generateNodes([n]);
    final shown = code.split('\n').first;
    if (n.kind == BK.call) {
      final spec = specFor(n.text);
      if (spec != null) return _fnHint(spec, code: shown);
      final user = _userFns[n.text];
      return TextSpan(
        children: [
          TextSpan(text: '${n.text}\n', style: _BlocksEditorState._hTitle),
          TextSpan(
            text: user != null
                ? 'Своя функция из этого скрипта${user.isEmpty ? '' : '; параметры: ${user.join(', ')}'}'
                : 'Такой команды нет в справочнике: она может быть из скрипта, '
                      'подключённого run_script, — или это опечатка.',
          ),
          TextSpan(text: '\n$shown', style: _BlocksEditorState._hCode),
        ],
      );
    }
    return TextSpan(
      children: [
        TextSpan(text: '${_kindTitle(n)}\n', style: _BlocksEditorState._hTitle),
        TextSpan(text: kindHints[n.kind] ?? ''),
        if (n.kind != BK.comment) TextSpan(text: '\n$shown', style: _BlocksEditorState._hCode),
      ],
    );
  }

  InlineSpan _paletteHint(PaletteItem item) {
    final shape = item.value ? shapeOf(item.code) : null;
    final node = item.value ? null : _BlocksEditorState._snippet(item.code).firstOrNull;
    final InlineSpan body;
    if (shape is XCall && specFor(shape.name) != null) {
      body = _fnHint(specFor(shape.name)!, code: item.code);
    } else if (node != null) {
      body = _blockHint(node);
    } else {
      body = TextSpan(
        children: [
          TextSpan(text: '${_valueTitle(shape)}\n', style: _BlocksEditorState._hTitle),
          TextSpan(text: _valueHint(shape)),
          TextSpan(text: '\n${item.code}', style: _BlocksEditorState._hCode),
        ],
      );
    }
    return TextSpan(
      children: [
        body,
        TextSpan(
          text: item.value
              ? '\n\nПеретащите в гнездо блока (или в скрипт). Щелчок — в гнездо, где стоит курсор.'
              : '\n\nПеретащите в скрипт или щёлкните — блок встанет после выделенного.',
          style: _BlocksEditorState._hMuted,
        ),
      ],
    );
  }

  String _valueTitle(XShape? s) => switch (s) {
    XOp(op: final op) => 'Оператор ${_opLabel(op)}',
    XNot() => 'не',
    XVar() => 'Переменная',
    XStr() => 'Текст',
    XNum() => 'Число',
    XBool() => 'Да / нет',
    _ => 'Значение',
  };

  String _valueHint(XShape? s) => switch (s) {
    XOp(op: final op) when (opLevels[op] ?? 9) <= 1 =>
      op == '&&' ? 'Верно, когда верны оба условия.' : 'Верно, когда верно хотя бы одно условие.',
    XOp(op: final op) when opLevels[op] == 2 || opLevels[op] == 3 =>
      'Сравнение: даёт true или false. Подходит для «если» и «пока».',
    XOp() => 'Арифметика: числа (а + ещё и склеивает текст).',
    XNot() => 'Наоборот: true становится false и наоборот.',
    XVar() => 'Значение переменной. Имя можно поменять прямо в блоке.',
    XStr() => 'Текст в кавычках.',
    XNum() => 'Число: 10, 2.5, проценты 50%, время 1s, случайное 800..1200.',
    XBool() => 'true — да, false — нет.',
    _ => '',
  };

  String _kindTitle(BNode n) => switch (n.kind) {
    BK.ifs => 'если',
    BK.repeat => n.args.isEmpty ? 'повторять всегда' : 'повторить',
    BK.whiles => 'пока',
    BK.withWin => 'в окне',
    BK.doWhile => 'делать … пока',
    BK.forIn => 'для каждого',
    BK.forC => 'цикл for',
    BK.func => 'функция',
    BK.ret => 'вернуть',
    BK.brk => 'выйти из цикла',
    BK.cont => 'следующий круг',
    BK.thr => 'ошибка',
    BK.tryc => 'попробовать',
    BK.sw => 'выбрать',
    BK.let => 'переменная',
    BK.set => 'изменить переменную',
    BK.comment => 'комментарий',
    _ => 'код',
  };
}
