// Draws blocks: colours, headers, words, drag handles, calls of functions.
part of '../blocks_editor.dart';

/// Text of a comment after a statement, without `//` or `/* */`.
String tailText(String tail) => tail
    .split('\n')
    .map((l) {
      var t = l.trim();
      if (t.startsWith('//')) t = t.substring(2);
      if (t.startsWith('/*')) t = t.substring(2);
      if (t.endsWith('*/')) t = t.substring(0, t.length - 2);
      return t.trim();
    })
    .where((t) => t.isNotEmpty)
    .join(' ');

/// A value that reads as a condition: dropped among the blocks it becomes
/// `if (value) { }`.
bool _isCondition(XShape s) => switch (s) {
  XOp(op: final op) => op != '??' && (opLevels[op] ?? 9) <= 3,
  XNot() || XBool() => true,
  XCall(name: final n) => specFor(n)?.returns?.startsWith('true') ?? false,
  _ => false,
};

String _opLabel(String op) => switch (op) {
  '==' || '===' => '=',
  '!=' || '!==' => '≠',
  '<=' => '≤',
  '>=' => '≥',
  '&&' => 'и',
  '||' => 'или',
  '*' => '×',
  '/' => '÷',
  '-' => '−',
  '%' => 'ост.',
  _ => op,
};

const _opGroups = [
  ['==', '!=', '>', '<', '>=', '<='],
  ['&&', '||'],
  ['+', '-', '*', '/', '%'],
];

// ------------------------------------------------------------------- render

/// Builds the widgets of blocks. [edit] — blocks can be changed;
/// [palette] — a sample in the palette or under the mouse while dragging
/// (no drop places, no marks).
class _R {
  final _BlocksEditorState ed;
  final bool edit;
  final bool palette;
  const _R(this.ed, {required this.edit, this.palette = false});

  bool get live => edit && !palette;

  Color _catColor(String id) => Color(catById(id).color);

  Color colorOf(BNode n) {
    switch (n.kind) {
      case BK.call:
        final spec = specFor(n.text);
        if (spec != null) return _catColor(spec.cat);
        return _catColor(ed._userFns.containsKey(n.text) ? 'funcs' : 'system');
      case BK.let || BK.set:
        return _catColor('vars');
      case BK.func:
        return _catColor('funcs');
      default:
        return _catColor('control');
    }
  }

  // ---- statements

  Widget stmt(BNode n, List<int> path) {
    final Widget w;
    if (n.kind == BK.comment) {
      w = _comment(n, path);
    } else if (n.kind == BK.code) {
      w = _code(n, path);
    } else if (n.isContainer) {
      w = _container(n, path);
    } else {
      w = _drop(
        path,
        _before(path),
        _after(path),
        header(n, path, colorOf(n), _pieces(n, path), radius: BorderRadius.circular(7)),
      );
    }
    if (palette) return w;
    final dragged = ed._dragging?.path;
    return Opacity(opacity: dragged != null && listEquals(dragged, path) ? 0.35 : 1, child: w);
  }

  Widget _drop(List<int> path, _Pos? before, _Pos? after, Widget child, {double indent = 0}) {
    if (!live) return child;
    return _Drop(ed: ed, before: before, after: after, indent: indent, child: child);
  }

  Widget word(String text, BNode n, List<int> path) => grab(n, path, Text(text, style: _wordStyle));

  Widget small(String text) => Text(text, style: _smallStyle);

  /// Makes [child] a handle to drag the block by.
  Widget grab(BNode n, List<int> path, Widget child) {
    if (!live) return child;
    final drag = _Drag.move(path, n);
    return Draggable<_Drag>(
      data: drag,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Builder(
        builder: (_) => ed._feedback(_R(ed, edit: false, palette: true).stmtPreview(n)),
      ),
      onDragStarted: () => ed._dragStart(drag),
      onDragUpdate: (d) => ed._dragMove(d.globalPosition),
      onDragEnd: (_) => ed._dragEnd(),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
  }

  /// A block without its inner blocks (shown under the mouse).
  Widget stmtPreview(BNode n) {
    if (!n.isContainer) return stmt(n, const [0]);
    final color = colorOf(n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header(
          n,
          const [0],
          color,
          _pieces(n, const [0]),
          radius: const BorderRadius.vertical(top: Radius.circular(7)),
        ),
        Container(
          width: 120,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
          ),
          alignment: Alignment.center,
          child: const Text('…', style: TextStyle(color: Colors.white70, fontSize: 11, height: 1)),
        ),
      ],
    );
  }

  /// The colored part of a block with its words and slots.
  Widget header(
    BNode n,
    List<int> path,
    Color color,
    List<Widget> pieces, {
    required BorderRadius radius,
    double minWidth = 0,
    bool lineNo = true,
  }) {
    final content = Container(
      constraints: BoxConstraints(minHeight: 30, minWidth: minWidth),
      padding: const EdgeInsets.fromLTRB(4, 3, 6, 3),
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 5,
        runSpacing: 4,
        children: [
          grab(n, path, const Icon(Icons.drag_indicator, size: 15, color: Color(0x99FFFFFF))),
          ...pieces,
          if (lineNo && n.tail != null) _tail(n.tail!),
          if (lineNo && !palette && n.line > 0) _line(n),
        ],
      ),
    );
    if (palette) return content;
    final marked = ListenableBuilder(
      listenable: ed._marks,
      builder: (context, child) {
        final run = identical(ed._runNode.value, n);
        final err = identical(ed._errNode.value, n);
        final caret = identical(ed._caretNode.value, n);
        final sel = listEquals(ed._sel, path);
        final reveal = ed._reveal;
        if (reveal != null && listEquals(reveal, path)) {
          ed._reveal = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Scrollable.ensureVisible(
              context,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
            Scrollable.ensureVisible(
              context,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
            );
          });
        }
        final Color? ring = err
            ? const Color(0xFFFF5A5F)
            : run
            ? Colors.white
            : sel
            ? _accent
            : caret
            ? const Color(0x996CB6FF)
            : null;
        // The glow goes under the block, the ring over it.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: run
                ? const [BoxShadow(color: Color(0xAA6CB6FF), blurRadius: 12, spreadRadius: 2)]
                : null,
          ),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: ring == null ? null : Border.all(color: ring, width: run || err ? 2.5 : 2),
            ),
            child: child,
          ),
        );
      },
      child: content,
    );
    return _HintRegion(
      ed: ed,
      content: () => ed._blockHint(n),
      child: Listener(
        onPointerDown: (e) => ed._onRightClick(e, (at) => ed._blockMenu(n, path, at)),
        child: GestureDetector(
          onTap: () {
            ed._select(path);
            ed._lastSlot = null;
            ed._focus.requestFocus();
          },
          child: marked,
        ),
      ),
    );
  }

  /// The comment written after the statement on its line.
  Widget _tail(String tail) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: Text(
      tailText(tail),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xD9FFF4C2),
        fontSize: 12,
        fontStyle: FontStyle.italic,
        height: 1.25,
      ),
    ),
  );

  /// Line number at the end of a block; a click sets a breakpoint.
  Widget _line(BNode n) {
    final onBreak = ed.widget.onBreakpoint;
    final bps = ed.widget.breakpoints;
    Widget build(bool on) => Tooltip(
      message:
          'Строка ${n.line}${onBreak == null
              ? ''
              : on
              ? ' — точка останова (щелчок убирает)'
              : ' — щелчок ставит точку останова'}',
      waitDuration: const Duration(milliseconds: 700),
      child: InkWell(
        onTap: onBreak == null ? null : () => onBreak(n.line),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: on
              ? BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Text(
            '${n.line}',
            style: TextStyle(
              fontSize: 10.5,
              color: on ? Colors.white : const Color(0x80FFFFFF),
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
    if (bps == null) return build(false);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: bps,
      builder: (_, set, _) => build(set.contains(n.line)),
    );
  }

  List<Widget> _pieces(BNode n, List<int> path) {
    final id = path.join('.');
    Widget w(String t) => word(t, n, path);
    ValueChanged<String>? setArg(int i) => live ? (v) => ed._setArg(path, i, v) : null;
    Widget arg(int i, PSpec? p, {VoidCallback? remove}) =>
        slot(n.args[i], spec: p, id: '$id/a$i', set: setArg(i), remove: remove);
    switch (n.kind) {
      case BK.call:
        return _call(n, path);
      case BK.let:
        return [
          w(n.extra == 'const' ? 'постоянная' : 'переменная'),
          _nameField(n, path, 'text', n.text, isIdentifier, look: _Look.variable),
          if (n.args.isNotEmpty) ...[
            w('='),
            arg(0, const PSpec('value', 'начальное значение: число, текст, результат команды')),
          ] else if (live)
            _plus([('= значение', 'задать начальное значение', () => ed._setArg(path, 0, '0'))]),
        ];
      case BK.set:
        final op = n.extra;
        final (first, mid) = switch (op) {
          '+=' => ('увеличить', 'на'),
          '-=' => ('уменьшить', 'на'),
          '*=' => ('умножить', 'на'),
          '/=' => ('разделить', 'на'),
          '%=' => ('остаток', 'от деления на'),
          '++' => ('увеличить', 'на 1'),
          '--' => ('уменьшить', 'на 1'),
          _ => ('задать', '='),
        };
        return [
          _opWord(n, path, first),
          _nameField(n, path, 'text', n.text, isValidExpr, look: _Look.variable),
          small(mid),
          if (op != '++' && op != '--' && n.args.isNotEmpty)
            arg(0, const PSpec('value', 'значение: число, текст, переменная, результат команды')),
        ];
      case BK.ret:
        return [
          w(n.args.isEmpty ? 'выйти из функции' : 'вернуть'),
          if (n.args.isNotEmpty) arg(0, const PSpec('value', 'что вернёт функция')),
        ];
      case BK.brk:
        return [w('выйти из цикла')];
      case BK.cont:
        return [w('следующий круг цикла')];
      case BK.thr:
        return [w('ошибка'), arg(0, const PSpec('value', 'текст ошибки'))];
      default:
        return [w(n.kind)];
    }
  }

  Widget _opWord(BNode n, List<int> path, String text) {
    if (!live) return Text(text, style: _wordStyle);
    return _menuWord(text, () async {
      final at = _lastTap;
      final v = await ed._menu<String>(at, [
        for (final (op, label) in const [
          ('=', 'задать = значение'),
          ('+=', 'увеличить на'),
          ('-=', 'уменьшить на'),
          ('*=', 'умножить на'),
          ('/=', 'разделить на'),
          ('++', 'увеличить на 1'),
          ('--', 'уменьшить на 1'),
        ])
          ed._item(op, label, keys: op),
      ]);
      if (v == null) return;
      ed._change(path, (x) {
        x.extra = v;
        if (v == '++' || v == '--') {
          x.args.clear();
        } else if (x.args.isEmpty) {
          x.args.add('1');
        }
      });
    });
  }

  static Offset _lastTap = Offset.zero;

  Widget _menuWord(String text, VoidCallback onTap, {TextStyle style = _wordStyle}) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTapDown: (d) => _lastTap = d.globalPosition,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: style),
          Icon(Icons.arrow_drop_down, size: 16, color: style.color),
        ],
      ),
    ),
  );

  List<Widget> _call(BNode n, List<int> path) {
    final id = path.join('.');
    final spec = specFor(n.text);
    final user = ed._userFns[n.text];
    Widget w(String t) => word(t, n, path);
    ValueChanged<String>? setArg(int i) => live ? (v) => ed._setArg(path, i, v) : null;
    final out = <Widget>[];
    if (spec == null) {
      out.add(w(n.text));
      for (var i = 0; i < n.args.length; i++) {
        final name = user != null && i < user.length ? user[i] : null;
        if (name != null) out.add(small(name));
        out.add(
          slot(
            n.args[i],
            spec: PSpec(
              name ?? 'значение ${i + 1}',
              name != null ? 'параметр «$name» функции ${n.text}' : 'значение для ${n.text}',
            ),
            id: '$id/a$i',
            set: setArg(i),
            remove: live ? () => ed._removeArgsFrom(path, i) : null,
          ),
        );
      }
      if (live && user != null && n.args.length < user.length) {
        out.add(
          _plus([
            for (var i = n.args.length; i < user.length; i++)
              (user[i], 'параметр функции ${n.text}', () => ed._addArgs(path, i)),
          ]),
        );
      }
    } else {
      out.addAll(
        labelPieces(spec, n.args, w, (i, p) {
          return slot(
            i < n.args.length ? n.args[i] : '',
            spec: p,
            id: '$id/a$i',
            set: setArg(i),
            remove: live && (p.optional || (p.rest && i > 0))
                ? () => ed._removeArgsFrom(path, i)
                : null,
          );
        }),
      );
    }
    for (final e in n.named.entries) {
      final p = namedSpec(e.key);
      out.add(small(p.label.isEmpty ? e.key : p.label));
      out.add(
        slot(
          e.value,
          spec: p,
          id: '$id/n:${e.key}',
          set: live ? (v) => ed._setNamed(path, e.key, v) : null,
          remove: live ? () => ed._setNamed(path, e.key, null) : null,
        ),
      );
      if (live) out.add(_close(() => ed._setNamed(path, e.key, null), 'Убрать «${p.label}»'));
    }
    if (spec != null && live) {
      out.addAll(_pickButtons(n, path, spec));
      final plus = _plusFor(n, path, spec);
      if (plus != null) out.add(plus);
    }
    return out;
  }

  static final _hole = RegExp(r'\{(\w+)\}');

  /// Words and slots of [spec] in the order of its label; arguments that
  /// are not in the label follow with their short names.
  List<Widget> labelPieces(
    FSpec spec,
    List<String> args,
    Widget Function(String) word,
    Widget Function(int i, PSpec p) slotAt,
  ) {
    final out = <Widget>[];
    final used = <int>{};
    var last = 0;
    for (final m in _hole.allMatches(spec.label)) {
      final before = spec.label.substring(last, m.start).trim();
      if (before.isNotEmpty) out.add(word(before));
      last = m.end;
      final i = spec.params.indexWhere((p) => p.name == m[1]);
      if (i < 0) continue;
      used.add(i);
      final p = spec.params[i];
      if (i < args.length || !p.optional) out.add(slotAt(i, p));
    }
    final tail = spec.label.substring(last).trim();
    if (tail.isNotEmpty) out.add(word(tail));
    for (var i = 0; i < args.length; i++) {
      if (used.contains(i)) continue;
      final rest = spec.params.isNotEmpty && spec.params.last.rest ? spec.params.last : null;
      final p = i < spec.params.length ? spec.params[i] : rest;
      if (p == null) {
        out.add(slotAt(i, PSpec('значение ${i + 1}', 'лишнее значение — команда его не ждёт')));
        continue;
      }
      if (p.label.isNotEmpty && i < spec.params.length) out.add(small(p.label));
      out.add(slotAt(i, p));
    }
    return out;
  }

  /// Buttons to take a point, a region or a colour from the screen.
  List<Widget> _pickButtons(BNode n, List<int> path, FSpec spec) {
    final ps = spec.params;
    final out = <Widget>[];
    final colorIdx = ps.indexWhere((p) => p.kind == PK.color);
    final hasColor = colorIdx >= 0 && colorIdx < n.args.length;
    var i = 0;
    var pickedColor = false;
    while (i + 1 < ps.length) {
      if (ps[i].kind == PK.coord && ps[i + 1].kind == PK.coord && i + 1 < n.args.length) {
        final area =
            i + 3 < ps.length &&
            ps[i + 2].kind == PK.size &&
            ps[i + 3].kind == PK.size &&
            i + 3 < n.args.length;
        if (area) {
          final idx = [i, i + 1, i + 2, i + 3];
          out.add(
            _tool(
              Icons.highlight_alt,
              'Выделить область на экране: два угла клавишей Ctrl',
              () => ed._pick(path, n.line, 'region', idx, null),
            ),
          );
          i += 4;
        } else {
          final idx = [i, i + 1];
          final withColor = hasColor && !pickedColor;
          pickedColor = pickedColor || withColor;
          final what = ps[i].hint.startsWith('откуда')
              ? 'точку «откуда»'
              : ps[i].hint.startsWith('куда')
              ? 'точку «куда»'
              : 'точку';
          out.add(
            _tool(
              Icons.my_location,
              'Взять $what кликом на экране${withColor ? ' (и её цвет)' : ''}',
              () => ed._pick(path, n.line, 'point', idx, withColor ? colorIdx : null),
            ),
          );
          i += 2;
        }
      } else {
        i++;
      }
    }
    if (hasColor && !pickedColor) {
      out.add(
        _tool(
          Icons.colorize,
          'Взять цвет кликом на экране',
          () => ed._pick(path, n.line, 'point', const [], colorIdx),
        ),
      );
    }
    return out;
  }

  Widget? _plusFor(BNode n, List<int> path, FSpec spec) {
    final entries = <(String, String, VoidCallback)>[];
    final ps = spec.params;
    var i = n.args.length;
    while (i < ps.length && ps[i].optional) {
      var j = i;
      if (ps[i].kind == PK.coord) {
        while (j + 1 < ps.length &&
            j - i < 3 &&
            (ps[j + 1].kind == PK.coord || ps[j + 1].kind == PK.size)) {
          j++;
        }
      }
      final group = ps.sublist(i, j + 1);
      final names = group.map((p) => p.name).join(', ');
      final title = group.length > 1
          ? '${group.first.label.isNotEmpty ? group.first.label : (group.length == 4 ? 'область' : 'точка')} ($names)'
          : (group.first.label.isNotEmpty
                ? '${group.first.label} (${group.first.name})'
                : group.first.name);
      final upTo = j;
      entries.add((title, group.first.hint, () => ed._addArgs(path, upTo)));
      i = j + 1;
    }
    if (ps.isNotEmpty && ps.last.rest && n.args.length >= ps.length) {
      entries.add(('ещё значение', ps.last.hint, () => ed._addArgs(path, n.args.length)));
    }
    for (final name in spec.named) {
      if (n.named.containsKey(name)) continue;
      final p = namedSpec(name);
      entries.add(('${p.label} ($name)', p.hint, () => ed._setNamed(path, name, p.def)));
    }
    return entries.isEmpty ? null : _plus(entries);
  }

  Widget _plus(List<(String, String, VoidCallback)> entries) =>
      _tool(Icons.add_circle_outline, 'Добавить параметр', () async {
        final v = await ed._menu<int>(_lastTap, [
          for (var i = 0; i < entries.length; i++)
            PopupMenuItem(
              value: i,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entries[i].$1, style: const TextStyle(fontSize: 13.5)),
                    Text(
                      entries[i].$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
        ]);
        if (v != null) entries[v].$3();
      });

  Widget _tool(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    waitDuration: const Duration(milliseconds: 400),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => _lastTap = d.globalPosition,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    ),
  );

  Widget _close(VoidCallback onTap, String tip) => Tooltip(
    message: tip,
    waitDuration: const Duration(milliseconds: 500),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: const Icon(Icons.close, size: 13, color: Color(0xAAFFFFFF)),
      ),
    ),
  );

  static String? _explain(String src, PSpec? p) {
    final s = src.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^-?[\d.]+%$').hasMatch(s)) return 'Сейчас: $s — проценты';
    if (s.contains('..') && !s.startsWith('"')) {
      return 'Сейчас: $s — случайное значение в этих пределах';
    }
    final unit = RegExp(r'^[\d.]+(ms|s|sec|m|min|h)$').firstMatch(s)?[1];
    if (unit != null) {
      return 'Сейчас: $s — ${switch (unit) {
        'ms' => 'миллисекунды',
        's' || 'sec' => 'секунды',
        'm' || 'min' => 'минуты',
        _ => 'часы',
      }}';
    }
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      return switch (p?.kind) {
        PK.ms => 'Сейчас: $s — миллисекунды',
        PK.coord || PK.size => 'Сейчас: $s — пиксели',
        _ => null,
      };
    }
    return null;
  }
}
