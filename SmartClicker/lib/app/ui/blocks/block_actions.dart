// Changes of the blocks: slots, insert, move, delete, copy, paste, drag & drop
// and keyboard shortcuts. Every change writes the code back.
part of 'blocks_editor.dart';

extension _BlocksEditorStateBlockActions on _BlocksEditorState {
  BNode? get _selected => _sel == null ? null : _doc?.resolve(_sel!);

  void _select(List<int>? path) {
    if (listEquals(path, _sel)) return;
    _setState(() => _sel = path);
  }

  (BNode?, int, int) _where(BlockDoc d, BNode n) {
    final p = n.parent;
    final list = d.listOf(n);
    return (p, p == null ? 0 : p.bodies.indexOf(list), list.indexOf(n));
  }

  void _setArg(List<int> path, int i, String v, {String? group}) => _apply((d) {
    final n = d.resolve(path);
    if (n == null) return;
    final spec = n.kind == BK.call ? specFor(n.text) : null;
    while (n.args.length <= i) {
      final k = n.args.length;
      n.args.add(
        spec == null
            ? 'null'
            : k < spec.params.length
            ? spec.params[k].def
            : spec.params.isNotEmpty
            ? spec.params.last.def
            : 'null',
      );
    }
    n.args[i] = v;
    BlockDoc.touch(n);
  }, group: group ?? '${path.join('.')}/a$i');

  /// Adds positional arguments with their default values up to index [upTo].
  void _addArgs(List<int> path, int upTo) => _apply((d) {
    final n = d.resolve(path);
    if (n == null) return;
    final spec = specFor(n.text);
    while (n.args.length <= upTo) {
      final k = n.args.length;
      final p = spec == null
          ? null
          : k < spec.params.length
          ? spec.params[k]
          : spec.params.lastOrNull;
      n.args.add(p?.def ?? 'null');
    }
    BlockDoc.touch(n);
  });

  void _removeArgsFrom(List<int> path, int i) => _apply((d) {
    final n = d.resolve(path);
    if (n == null || i >= n.args.length) return;
    n.args.removeRange(i, n.args.length);
    BlockDoc.touch(n);
  });

  void _setNamed(List<int> path, String key, String? v) => _apply((d) {
    final n = d.resolve(path);
    if (n == null) return;
    if (v == null) {
      n.named.remove(key);
    } else {
      n.named[key] = v;
    }
    BlockDoc.touch(n);
  }, group: v == null ? null : '${path.join('.')}/n:$key');

  void _setField(List<int> path, String field, String v) => _apply((d) {
    final n = d.resolve(path);
    if (n == null) return;
    if (field == 'text') {
      n.text = v;
    } else {
      n.extra = v;
    }
    if (n.kind == BK.comment) n.extra = '';
    BlockDoc.touch(n);
  }, group: '${path.join('.')}/$field');

  void _change(List<int> path, void Function(BNode n) f) => _apply((d) {
    final n = d.resolve(path);
    if (n == null) return;
    f(n);
    BlockDoc.touch(n);
  });

  void _deletePath(List<int> path) {
    _apply((d) {
      final n = d.resolve(path);
      if (n != null) d.remove(n);
    });
    final doc = _doc;
    if (doc != null && doc.resolve(path) == null) {
      // Select the block that took its place, or the one before.
      final prev = [...path];
      if (prev.last > 0) {
        prev[prev.length - 1]--;
        _sel = doc.resolve(prev) != null ? prev : null;
      } else {
        _sel = _ownerOf(path);
      }
    }
    _setState(() {});
  }

  void _duplicate(List<int> path) {
    List<BNode> copy = const [];
    _apply((d) {
      final n = d.resolve(path);
      if (n == null) return;
      final (owner, body, index) = _where(d, n);
      copy = parseSnippet(generateNodes([n], unit: d.unit));
      d.insert(owner, body, index + 1, copy);
    }, select: (_) => copy.firstOrNull);
  }

  void _copy(BNode n, {bool cut = false}) {
    final doc = _doc;
    if (doc == null) return;
    Clipboard.setData(ClipboardData(text: generateNodes([n], unit: doc.unit)));
    widget.host.notify?.call(cut ? 'Вырезано' : 'Скопировано', 'Код блока в буфере обмена');
    if (cut) _deletePath(doc.pathOf(n));
  }

  Future<void> _paste() async {
    if (!_editable) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return;
    List<BNode> nodes;
    try {
      nodes = parseSnippet(text);
    } on Object {
      widget.host.notify?.call('Не вставлено', 'В буфере обмена не код скрипта (в нём ошибка)');
      return;
    }
    _insertAtSelection(nodes);
  }

  _Pos _insertPos() {
    final sel = _selected;
    if (sel == null) return _Pos(null, 0, _doc!.nodes.length);
    return _after(_doc!.pathOf(sel));
  }

  void _insertAtSelection(List<BNode> nodes) {
    if (nodes.isEmpty) return;
    final pos = _insertPos();
    _apply((d) {
      final owner = pos.owner == null ? null : d.resolve(pos.owner!);
      d.insert(owner, pos.body, pos.index, nodes);
    }, select: (_) => nodes.first);
  }

  void _shift(List<int> path, int delta) {
    BNode? moved;
    _apply((d) {
      final n = d.resolve(path);
      if (n == null) return;
      final (owner, body, index) = _where(d, n);
      final list = d.body(owner, body);
      final to = index + delta;
      if (to < 0 || to >= list.length) return;
      d.move(n, owner, body, delta > 0 ? to + 1 : to);
      moved = n;
    }, select: (_) => moved);
  }

  /// All blocks in the order they are shown.
  List<List<int>> _order() {
    final doc = _doc;
    if (doc == null) return const [];
    return [for (final n in doc.all) doc.pathOf(n)];
  }

  void _step(int delta) {
    final order = _order();
    if (order.isEmpty) return;
    final i = _sel == null ? -1 : order.indexWhere((p) => listEquals(p, _sel));
    final j = (i < 0 ? (delta > 0 ? 0 : order.length - 1) : i + delta).clamp(0, order.length - 1);
    _setState(() {
      _sel = order[j];
      _reveal = order[j];
    });
  }

  List<BNode> _nodesFor(PaletteItem item, BlockDoc doc) {
    if (!item.value) return parseSnippet(item.code);
    final shape = shapeOf(item.code);
    if (_isCondition(shape)) return parseSnippet('if (${item.code}) {\n}');
    final base = shape is XCall ? (specFor(shape.name)?.saveAs ?? 'value') : 'value';
    final used = variableNames(doc).toSet();
    var name = base;
    for (var k = 2; used.contains(name); k++) {
      name = '$base$k';
    }
    return parseSnippet('let $name = ${item.code}');
  }

  bool _canDrop(_Drag d, _Pos p) {
    if (!_editable) return false;
    final from = d.path;
    if (from != null && p.owner != null && _startsWith(p.owner!, from)) return false;
    return true;
  }

  void _dropAt(_Drag d, _Pos p) {
    if (!_canDrop(d, p)) return;
    List<BNode> added = const [];
    BNode? moved;
    _apply((doc) {
      final owner = p.owner == null ? null : doc.resolve(p.owner!);
      if (p.owner != null && owner == null) return;
      if (d.path != null) {
        final n = doc.resolve(d.path!);
        if (n == null) return;
        if (doc.move(n, owner, p.body, p.index)) moved = n;
      } else {
        added = _nodesFor(d.item!, doc);
        doc.insert(owner, p.body, p.index, added);
      }
    }, select: (_) => moved ?? added.firstOrNull);
    // The floating list would hide the new block.
    if (d.item != null && _floatOpen) _setState(() => _floatOpen = false);
  }

  void _addFromPalette(PaletteItem item) {
    if (!_editable) return;
    final slot = _lastSlot;
    if (item.value && slot != null) {
      slot.set(item.code);
      if (_floatOpen) _setState(() => _floatOpen = false);
      return;
    }
    _dropAt(_Drag.palette(item), _insertPos());
  }

  void _pick(List<int> path, int line, String mode, List<int> idx, int? colorIdx) {
    final pick = widget.host.pick;
    if (pick == null || !_editable) return;
    pick(mode, line, (values, color) {
      if (!mounted) return;
      _apply((d) {
        final n = d.resolve(path);
        if (n == null) return;
        for (var k = 0; k < idx.length && k < values.length; k++) {
          if (idx[k] < n.args.length) n.args[idx[k]] = values[k];
        }
        if (colorIdx != null && colorIdx < n.args.length && color.isNotEmpty) {
          n.args[colorIdx] = quote(color);
        }
        BlockDoc.touch(n);
      });
    });
  }

  void _dragStart(_Drag d) {
    _hints.hideAll();
    _setState(() => _dragging = d);
  }

  void _dragMove(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    const edge = 40.0;
    var speed = 0.0;
    if (local.dx >= 0 && local.dx <= box.size.width) {
      if (local.dy < edge) speed = -(edge - local.dy).clamp(0, edge) / 2;
      if (local.dy > box.size.height - edge) {
        speed = (local.dy - box.size.height + edge).clamp(0, edge) / 2;
      }
    }
    _scrollSpeed = speed;
    if (speed != 0 && _autoScroll == null) {
      _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (_scrollSpeed == 0 || !_scroll.hasClients) {
          t.cancel();
          _autoScroll = null;
          return;
        }
        final p = _scroll.position;
        _scroll.jumpTo((p.pixels + _scrollSpeed).clamp(0.0, p.maxScrollExtent));
      });
    }
  }

  void _dragEnd() {
    _scrollSpeed = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
    if (_dragging != null && mounted) _setState(() => _dragging = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Keys typed into a slot belong to the slot.
    if (FocusManager.instance.primaryFocus != _focus) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed, shift = kb.isShiftPressed, alt = kb.isAltPressed;
    KeyEventResult done(void Function() f) {
      f();
      return KeyEventResult.handled;
    }

    if (ctrl && k == LogicalKeyboardKey.keyZ) return done(shift ? _redoAct : _undoAct);
    if (ctrl && k == LogicalKeyboardKey.keyY) return done(_redoAct);
    if (ctrl && k == LogicalKeyboardKey.keyV) return done(_paste);
    if (!ctrl && !alt && k == LogicalKeyboardKey.arrowDown) return done(() => _step(1));
    if (!ctrl && !alt && k == LogicalKeyboardKey.arrowUp) return done(() => _step(-1));
    final sel = _selected;
    if (sel == null) return KeyEventResult.ignored;
    final path = _doc!.pathOf(sel);
    if (k == LogicalKeyboardKey.escape) return done(() => _select(null));
    if (!_editable) {
      if (ctrl && k == LogicalKeyboardKey.keyC) return done(() => _copy(sel));
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      return done(() => _deletePath(path));
    }
    if (ctrl && k == LogicalKeyboardKey.keyD) return done(() => _duplicate(path));
    if (ctrl && k == LogicalKeyboardKey.keyC) return done(() => _copy(sel));
    if (ctrl && k == LogicalKeyboardKey.keyX) return done(() => _copy(sel, cut: true));
    if (alt && k == LogicalKeyboardKey.arrowUp) return done(() => _shift(path, -1));
    if (alt && k == LogicalKeyboardKey.arrowDown) return done(() => _shift(path, 1));
    return KeyEventResult.ignored;
  }
}
