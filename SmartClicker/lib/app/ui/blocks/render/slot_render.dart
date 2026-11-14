// Draws slots: values, nested value blocks, operators, choices, helpers
// (pickers, lists of pictures and windows).
part of '../blocks_editor.dart';

Widget _swatch(Color c) => Container(
  width: 12,
  height: 12,
  decoration: BoxDecoration(
    color: c,
    borderRadius: BorderRadius.circular(3),
    border: Border.all(color: const Color(0x55000000)),
  ),
);

Color? _hexColor(String s) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(s.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

/// How a slot looks.
enum _Look {
  literal,
  variable,
  name,
  code,
  bad;

  BoxDecoration get decoration => switch (this) {
    _Look.literal => BoxDecoration(
      color: const Color(0xFFF2F4F8),
      borderRadius: BorderRadius.circular(11),
    ),
    _Look.variable => BoxDecoration(
      color: const Color(0xFFE8833A),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0x66FFFFFF)),
    ),
    _Look.name => BoxDecoration(
      color: const Color(0x33000000),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0x66FFFFFF)),
    ),
    _Look.code => BoxDecoration(
      color: const Color(0xFF22252D),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _cardBorder),
    ),
    _Look.bad => BoxDecoration(
      color: const Color(0xFF3A1F22),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFFF5A5F), width: 1.5),
    ),
  };

  TextStyle get style => switch (this) {
    _Look.literal => _chipText,
    _Look.variable || _Look.name => const TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    _ => _mono.copyWith(color: _text),
  };
}

// --------------------------------------------------------------- slot field

extension _RenderSlotRender on _R {
  /// A place for a value inside a block.
  Widget slot(
    String src, {
    required PSpec? spec,
    required String id,
    required ValueChanged<String>? set,
    VoidCallback? remove,
  }) {
    final shape = shapeOf(src);
    final editing = live && ed._editingSlot == id;
    Widget body;
    if (!editing && shape is XCall) {
      body = _reporter(shape, id, set);
    } else if (!editing && shape is XOp) {
      body = _opBlock(shape, id, set);
    } else if (!editing && shape is XNot) {
      body = _notBlock(shape, id, set);
    } else if (!editing && spec?.kind == PK.choice && spec!.options.containsKey(src.trim())) {
      body = _choice(spec.options, src.trim(), set);
    } else if (!editing && shape is XBool) {
      body = _choice(const {'true': 'да', 'false': 'нет'}, src.trim(), set);
    } else {
      body = _field(src, shape, id, spec, set);
    }
    final helper = live && set != null ? _helper(spec, src, shape, set) : null;
    if (helper != null) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [body, const SizedBox(width: 2), helper],
      );
    }
    if (palette) return body;
    // Values dropped from the palette go into the slot.
    if (live && set != null) {
      final inner = body;
      body = DragTarget<_Drag>(
        onWillAcceptWithDetails: (d) => d.data.isValue,
        onAcceptWithDetails: (d) => set(d.data.item!.code),
        builder: (context, cand, _) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: cand.isEmpty ? null : Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: inner,
        ),
      );
      final dropTarget = body;
      body = Listener(
        onPointerDown: (e) => ed._onRightClick(e, (at) => ed._slotMenu(at, src, spec, set, remove)),
        child: dropTarget,
      );
    }
    return _HintRegion(ed: ed, content: () => _slotHint(spec, src, shape), child: body);
  }

  Widget? _helper(PSpec? spec, String src, XShape shape, ValueChanged<String> set) {
    final host = ed.widget.host;
    switch (spec?.kind) {
      case PK.picture when host.pictures != null:
        return _listButton('Выбрать картинку', () => host.pictures!(), set);
      case PK.script when host.scripts != null:
        return _listButton('Выбрать скрипт', () => host.scripts!(), set);
      case PK.window when host.windows != null:
        return _listButton('Выбрать из открытых окон', () {
          final seen = <String>{};
          return [
            for (final (title, _) in host.windows!())
              if (title.isNotEmpty && seen.add(title)) title,
          ];
        }, set);
      case PK.process when host.windows != null:
        return _listButton('Выбрать из запущенных программ', () {
          final seen = <String>{};
          return [
            for (final (_, process) in host.windows!())
              if (process.isNotEmpty && seen.add(process.toLowerCase())) process,
          ];
        }, set);
      case PK.key when host.captureKey != null:
        return _tool(Icons.keyboard, 'Нажать клавишу или сочетание', () async {
          final combo = await host.captureKey!(ed.context);
          if (combo != null && combo.isNotEmpty) set(quote(combo));
        });
      case PK.choice:
        final options = spec!.options;
        if (options.containsKey(src.trim())) return null;
        return _tool(Icons.arrow_drop_down, 'Выбрать', () async {
          final v = await ed._menu<String>(_R._lastTap, [
            for (final e in options.entries) ed._item(e.key, e.value, keys: e.key),
          ]);
          if (v != null) set(v);
        });
      default:
        return null;
    }
  }

  Widget _listButton(String tip, List<String> Function() items, ValueChanged<String> set) =>
      _tool(Icons.arrow_drop_down, tip, () async {
        final list = items();
        if (list.isEmpty) {
          ed.widget.host.notify?.call(tip, 'Список пуст');
          return;
        }
        final v = await ed._menu<String>(_R._lastTap, [
          for (final s in list.take(40))
            PopupMenuItem(
              value: s,
              height: 32,
              child: Text(
                s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ]);
        if (v != null) set(quote(v));
      });

  Widget _field(String src, XShape shape, String id, PSpec? spec, ValueChanged<String>? set) {
    final textKinds = {PK.text, PK.picture, PK.window, PK.process, PK.script, PK.key, PK.color};
    final textMode = shape is XStr || (shape is XEmpty && textKinds.contains(spec?.kind));
    final look = switch (shape) {
      XVar() => _Look.variable,
      XRaw(valid: false) => _Look.bad,
      XRaw() => _Look.code,
      XNull() => _Look.code,
      _ => _Look.literal,
    };
    final color = shape is XStr ? _hexColor(shape.value) : null;
    if (!live || set == null) {
      final shown = shape is XStr ? shape.value : src;
      return _chip(shown.isEmpty ? (spec?.def ?? '') : shown, look, color: color);
    }
    return _SlotField(
      key: ValueKey(id),
      ed: ed,
      id: id,
      src: src,
      textMode: textMode,
      look: look,
      swatch: color,
      onChanged: set,
    );
  }

  Widget _reporter(XCall c, String id, ValueChanged<String>? set) {
    final spec = specFor(c.name);
    final user = ed._userFns[c.name];
    final color = spec != null ? _catColor(spec.cat) : _catColor(user != null ? 'funcs' : 'system');
    ValueChanged<String>? setArg(int i) => set == null
        ? null
        : (v) {
            final args = [...c.args];
            while (args.length <= i) {
              args.add(
                spec != null && args.length < spec.params.length
                    ? spec.params[args.length].def
                    : 'null',
              );
            }
            args[i] = v;
            set(buildCall(c.name, args, c.named));
          };
    Widget word(String t) => Text(t, style: _wordStyle);
    final pieces = <Widget>[];
    if (spec == null) {
      pieces.add(word(c.name));
      for (var i = 0; i < c.args.length; i++) {
        pieces.add(
          slot(
            c.args[i],
            spec: PSpec(
              user != null && i < user.length ? user[i] : 'значение ${i + 1}',
              'значение для ${c.name}',
            ),
            id: '$id/$i',
            set: setArg(i),
          ),
        );
      }
    } else {
      pieces.addAll(
        labelPieces(spec, c.args, word, (i, p) {
          return slot(i < c.args.length ? c.args[i] : '', spec: p, id: '$id/$i', set: setArg(i));
        }),
      );
    }
    for (final e in c.named.entries) {
      final p = namedSpec(e.key);
      pieces.add(small(p.label.isEmpty ? e.key : p.label));
      pieces.add(
        slot(
          e.value,
          spec: p,
          id: '$id/n:${e.key}',
          set: set == null ? null : (v) => set(buildCall(c.name, c.args, {...c.named, e.key: v})),
        ),
      );
    }
    return _pill(
      color,
      pieces,
      hint: () => spec != null
          ? ed._fnHint(spec, code: buildCall(c.name, c.args, c.named))
          : TextSpan(text: c.name),
    );
  }

  Widget _opBlock(XOp o, String id, ValueChanged<String>? set) {
    final group = _opGroups.firstWhere((g) => g.contains(o.op), orElse: () => [o.op]);
    final opWidget = set == null || !live || group.length < 2
        ? Text(_opLabel(o.op), style: _wordStyle)
        : _menuWord(_opLabel(o.op), () async {
            final v = await ed._menu<String>(_R._lastTap, [
              for (final op in group) ed._item(op, _opLabel(op), keys: op),
            ]);
            if (v != null) set(buildOp(v, o.left, o.right));
          });
    final logic = (opLevels[o.op] ?? 9) <= 1;
    final valueSpec = PSpec(
      'value',
      logic ? 'условие' : 'значение: число, текст, переменная, результат команды',
    );
    return _pill(
      _catColor('ops'),
      [
        slot(
          o.left,
          spec: valueSpec,
          id: '$id/l',
          set: set == null ? null : (v) => set(buildOp(o.op, v, o.right)),
        ),
        opWidget,
        slot(
          o.right,
          spec: valueSpec,
          id: '$id/r',
          set: set == null ? null : (v) => set(buildOp(o.op, o.left, v)),
        ),
      ],
      hint: () => TextSpan(
        children: [
          TextSpan(text: 'Оператор ${_opLabel(o.op)}\n', style: _BlocksEditorState._hTitle),
          TextSpan(text: ed._valueHint(o)),
        ],
      ),
    );
  }

  Widget _notBlock(XNot x, String id, ValueChanged<String>? set) => _pill(
    _catColor('ops'),
    [
      Text('не', style: _wordStyle),
      slot(
        x.operand,
        spec: const PSpec('condition', 'условие, которое переворачивается'),
        id: '$id/x',
        set: set == null ? null : (v) => set(buildNot(v)),
      ),
    ],
    hint: () => TextSpan(
      children: [
        const TextSpan(text: 'не\n', style: _BlocksEditorState._hTitle),
        TextSpan(text: ed._valueHint(x)),
      ],
    ),
  );

  Widget _pill(Color color, List<Widget> pieces, {required InlineSpan Function() hint}) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 3,
        children: pieces,
      ),
    );
    if (palette) return pill;
    return _HintRegion(ed: ed, content: hint, child: pill);
  }

  Widget _choice(Map<String, String> options, String value, ValueChanged<String>? set) {
    final label = options[value] ?? value;
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _chipText),
          const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF555B69)),
        ],
      ),
    );
    if (!live || set == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => _R._lastTap = d.globalPosition,
        onTap: () async {
          final v = await ed._menu<String>(_R._lastTap, [
            for (final e in options.entries) ed._item(e.key, e.value, keys: e.key),
          ]);
          if (v != null) set(v);
        },
        child: chip,
      ),
    );
  }

  InlineSpan _slotHint(PSpec? p, String src, XShape shape) {
    final title = p == null
        ? 'значение'
        : p.label.isNotEmpty
        ? '${p.label} (${p.name})'
        : p.name;
    final path = p?.kind == PK.picture && shape is XStr && shape.value.isNotEmpty
        ? ed.widget.host.imagePath?.call(shape.value)
        : null;
    return TextSpan(
      children: [
        TextSpan(text: '$title\n', style: _BlocksEditorState._hTitle),
        TextSpan(text: p?.hint ?? ''),
        if (_R._explain(src, p) case final e?)
          TextSpan(text: '\n$e', style: _BlocksEditorState._hMuted),
        if (path != null)
          WidgetSpan(
            child: _Picture(path: path, name: (shape as XStr).value),
          ),
        if (live && p != null)
          const TextSpan(
            text: '\nПравая кнопка — ввести как код или подставить переменную',
            style: _BlocksEditorState._hMuted,
          ),
      ],
    );
  }

  Widget _chip(String text, _Look look, {Color? color}) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: look.decoration,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[_swatch(color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: look.style),
        ),
      ],
    ),
  );
}
