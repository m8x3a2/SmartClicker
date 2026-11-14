// Block constructor: the widget, its state and syncing with the code.
// Parts: actions, menus, canvas, palette, hints, slots, render/.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/blocks/blocks.dart';
import '../../../core/blocks/catalog.dart';
import '../../../core/blocks/expr.dart';
import '../../../core/lang/values.dart' show ScriptError;
import '../editor/code_editor.dart' show codeStyle;

part 'block_actions.dart';
part 'block_menus.dart';
part 'canvas.dart';
part 'palette.dart';
part 'hints.dart';
part 'render/block_render.dart';
part 'render/container_render.dart';
part 'render/note_render.dart';
part 'render/slot_render.dart';
part 'slot_field.dart';
part 'drop_zone.dart';

const _accent = Color(0xFF6CB6FF);

const _muted = Color(0xFF8B92A1);

const _cardBg = Color(0xFF262A33);

const _cardBorder = Color(0xFF3B4254);

const _canvasBg = Color(0xFF15171C);

const _railBg = Color(0xFF181A20);

const _text = Color(0xFFD7DAE0);

const _wordStyle = TextStyle(
  color: Colors.white,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  height: 1.25,
);

const _smallStyle = TextStyle(
  color: Color(0xE6FFFFFF),
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.25,
);

const _chipText = TextStyle(color: Color(0xFF1E2128), fontSize: 12.5, height: 1.25);

final _mono = codeStyle.copyWith(fontSize: 12.5, height: 1.3);

/// What the block editor may ask of the application.
class BlocksHost {
  /// Full path of a picture by its name (`files\name.png`).
  final String Function(String name)? imagePath;
  final List<String> Function()? pictures;
  final List<String> Function()? scripts;

  /// Open windows: (title, process).
  final List<(String, String)> Function()? windows;
  final Future<String?> Function(BuildContext context)? captureKey;

  /// Lets the user click a point (`point`) or mark a region (`region`);
  /// [line] is the line of the block (a `use_window` above it counts).
  /// [done] gets the coordinates as code and the colour of the point.
  final void Function(String mode, int line, void Function(List<String> values, String color) done)?
  pick;
  final void Function(String title, String text)? notify;
  const BlocksHost({
    this.imagePath,
    this.pictures,
    this.scripts,
    this.windows,
    this.captureKey,
    this.pick,
    this.notify,
  });
}

/// Visual editor of a script: blocks that can be dragged, nested and
/// edited. The code in [controller] is the only source of truth: the
/// blocks are parsed from it and every change writes it back.
class BlocksEditor extends StatefulWidget {
  final TextEditingController controller;
  final ValueListenable<int> currentLine;
  final ValueListenable<int> errorLine;
  final ValueListenable<Set<int>>? breakpoints;
  final void Function(int line)? onBreakpoint;
  final bool readOnly;

  /// Explanations under the mouse.
  final bool hints;

  /// The list of blocks next to the categories is open.
  final bool palette;
  final ValueChanged<bool>? onPalette;

  /// The code is visible next to the blocks: the block at the text cursor
  /// is marked.
  final bool besideCode;

  /// "Show the code" for a syntax error at a line.
  final void Function(int line)? onShowCode;
  final BlocksHost host;
  const BlocksEditor({
    super.key,
    required this.controller,
    required this.currentLine,
    required this.errorLine,
    this.breakpoints,
    this.onBreakpoint,
    this.readOnly = false,
    this.hints = true,
    this.palette = true,
    this.onPalette,
    this.besideCode = false,
    this.onShowCode,
    this.host = const BlocksHost(),
  });

  @override
  State<BlocksEditor> createState() => _BlocksEditorState();
}

/// Where a block goes: position [index] of body [body] of the block at
/// [owner] (null — the script itself).
class _Pos {
  final List<int>? owner;
  final int body;
  final int index;
  const _Pos(this.owner, this.body, this.index);
}

/// What is being dragged: a block of the script or an item of the palette.
class _Drag {
  final List<int>? path;
  final BNode? node;
  final PaletteItem? item;
  const _Drag.move(List<int> this.path, BNode this.node) : item = null;
  const _Drag.palette(PaletteItem this.item) : path = null, node = null;

  /// Can go into a slot.
  bool get isValue {
    final i = item;
    if (i == null) return false;
    if (i.value) return true;
    final s = shapeOf(i.code);
    return s is XCall && (specFor(s.name)?.isValue ?? false);
  }
}

/// The slot that had the keyboard last: a click on a value in the
/// palette puts it there.
class _SlotRef {
  final String id;
  final ValueChanged<String> set;
  const _SlotRef(this.id, this.set);
}

List<int>? _ownerOf(List<int> path) => path.length < 3 ? null : path.sublist(0, path.length - 2);

int _bodyOf(List<int> path) => path.length < 3 ? 0 : path[path.length - 2];

_Pos _before(List<int> path) => _Pos(_ownerOf(path), _bodyOf(path), path.last);

_Pos _after(List<int> path) => _Pos(_ownerOf(path), _bodyOf(path), path.last + 1);

bool _startsWith(List<int> path, List<int> prefix) =>
    path.length >= prefix.length && listEquals(path.sublist(0, prefix.length), prefix);

class _BlocksEditorState extends State<BlocksEditor> {
  BlockDoc? _doc;
  String? _error;
  int _errLine = 0;
  String _parsed = '';
  Timer? _debounce;
  bool _writing = false;
  Map<String, List<String>> _userFns = const {};

  final _undo = <String>[];
  final _redo = <String>[];
  String? _group;
  DateTime _groupAt = DateTime(0);

  List<int>? _sel;
  List<int>? _reveal;
  final _runNode = ValueNotifier<BNode?>(null);
  final _errNode = ValueNotifier<BNode?>(null);
  final _caretNode = ValueNotifier<BNode?>(null);
  late Listenable _marks;

  final _scroll = ScrollController();
  final _paletteScroll = ScrollController();
  final _canvasKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'blocks');
  final _search = TextEditingController();
  String _cat = 'control';

  /// Narrow place (next to the code): the list of blocks floats over the
  /// canvas, opened by a category and hidden while a block is dragged.
  bool _floating = false;
  bool _floatOpen = false;

  _Drag? _dragging;
  Timer? _autoScroll;
  double _scrollSpeed = 0;

  String? _editingSlot;
  _SlotRef? _lastSlot;

  /// The right click that already opened a menu: slots get it before the
  /// block around them, and the block must not open its own menu too.
  int? _menuPointer;

  /// [f] opens a menu for a right click, unless an inner part did.
  void _onRightClick(PointerDownEvent e, void Function(Offset at) f) {
    if (e.buttons & kSecondaryMouseButton == 0 || _menuPointer == e.pointer) return;
    _menuPointer = e.pointer;
    f(e.position);
  }

  late final _hints = _Hints(this);

  static final _snippets = <String, List<BNode>>{};

  @override
  void initState() {
    super.initState();
    _reparse(widget.controller.text);
    widget.controller.addListener(_onText);
    widget.currentLine.addListener(_onLines);
    widget.errorLine.addListener(_onLines);
    _marks = _merge();
    _onLines();
  }

  Listenable _merge() => Listenable.merge([
    _runNode,
    _errNode,
    _caretNode,
    if (widget.breakpoints != null) widget.breakpoints!,
  ]);

  @override
  void didUpdateWidget(BlocksEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _reparse(widget.controller.text);
    }
    if (old.currentLine != widget.currentLine || old.errorLine != widget.errorLine) {
      old.currentLine.removeListener(_onLines);
      old.errorLine.removeListener(_onLines);
      widget.currentLine.addListener(_onLines);
      widget.errorLine.addListener(_onLines);
    }
    if (old.breakpoints != widget.breakpoints) _marks = _merge();
    if (!widget.besideCode && _caretNode.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _caretNode.value = null);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    widget.currentLine.removeListener(_onLines);
    widget.errorLine.removeListener(_onLines);
    _debounce?.cancel();
    _autoScroll?.cancel();
    _hints.hideAll();
    _scroll.dispose();
    _paletteScroll.dispose();
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- code sync

  void _onText() {
    if (_writing) return;
    final text = widget.controller.text;
    if (text == _parsed) {
      _syncCaret();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _reparse(widget.controller.text));
      _syncCaret();
    });
  }

  void _reparse(String text) {
    try {
      _doc = parseBlocks(text);
      _error = null;
    } on ScriptError catch (e) {
      _error = e.message;
      _errLine = e.line;
    } on Object catch (e) {
      _error = '$e';
      _errLine = 0;
    }
    _parsed = text;
    final doc = _doc;
    _userFns = doc == null ? const {} : userFunctions(doc);
    _onLines();
  }

  void _onLines() {
    final doc = _doc;
    final cur = widget.currentLine.value, err = widget.errorLine.value;
    final run = cur > 0 && doc != null ? doc.at(cur) : null;
    if (!identical(run, _runNode.value) && run != null) _reveal = doc!.pathOf(run);
    _runNode.value = run;
    final e = err > 0 && doc != null ? doc.at(err) : null;
    if (!identical(e, _errNode.value) && e != null) _reveal = doc!.pathOf(e);
    _errNode.value = e;
  }

  void _syncCaret() {
    if (!widget.besideCode) return;
    final doc = _doc;
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    if (doc == null || !sel.isValid || sel.start > text.length) return;
    final line = '\n'.allMatches(text.substring(0, sel.start)).length + 1;
    final n = doc.at(line);
    if (!identical(n, _caretNode.value) && n != null) _reveal = doc.pathOf(n);
    _caretNode.value = n;
  }

  /// Changes the blocks and writes the code back. Edits with the same
  /// [group] (typing in one slot) are undone together.
  void _apply(
    void Function(BlockDoc doc) change, {
    String? group,
    BNode? Function(BlockDoc doc)? select,
  }) {
    final doc = _doc;
    if (doc == null || widget.readOnly || _error != null) return;
    _hints.hideAll();
    final before = widget.controller.text;
    change(doc);
    final picked = select?.call(doc);
    final selPath = picked != null && doc.all.any((n) => identical(n, picked))
        ? doc.pathOf(picked)
        : null;
    final code = doc.code();
    if (code == before) {
      setState(() {});
      return;
    }
    final now = DateTime.now();
    if (group == null || group != _group || now.difference(_groupAt).inMilliseconds > 1500) {
      _undo.add(before);
      if (_undo.length > 200) _undo.removeAt(0);
    }
    _redo.clear();
    _group = group;
    _groupAt = now;
    if (group == null) _lastSlot = null;
    _write(code);
    if (selPath != null) {
      _sel = selPath;
      _reveal = selPath;
    }
  }

  void _write(String code) {
    final old = widget.controller.text;
    final minLen = math.min(old.length, code.length);
    var pre = 0;
    while (pre < minLen && old.codeUnitAt(pre) == code.codeUnitAt(pre)) {
      pre++;
    }
    var suf = 0;
    while (suf < minLen - pre &&
        old.codeUnitAt(old.length - 1 - suf) == code.codeUnitAt(code.length - 1 - suf)) {
      suf++;
    }
    // The caret goes to the end of the changed line: breakpoints below the
    // change move with their lines, and F6 inserts after the block.
    var caret = code.length - suf;
    if (caret > 0 && caret > pre && code[caret - 1] == '\n') caret--;
    final eol = code.indexOf('\n', caret);
    caret = eol < 0 ? code.length : eol;
    setState(() => _reparse(code));
    _writing = true;
    widget.controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: caret),
    );
    _writing = false;
  }

  void _undoAct() {
    if (_undo.isEmpty || widget.readOnly) return;
    _redo.add(widget.controller.text);
    _group = null;
    _write(_undo.removeLast());
  }

  void _redoAct() {
    if (_redo.isEmpty || widget.readOnly) return;
    _undo.add(widget.controller.text);
    _group = null;
    _write(_redo.removeLast());
  }

  bool get _editable => !widget.readOnly && _error == null && _doc != null;

  static const _railWidth = 62.0;
  static const _flyWidth = 228.0;

  /// setState for the parts of the editor (extensions may not call it).
  void _setState(VoidCallback f) => setState(f);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _hints.hideAll(),
      onPointerUp: (_) {
        if (_dragging != null) Future.microtask(_dragEnd);
      },
      child: LayoutBuilder(
        builder: (context, c) {
          // Less than ~380 px left for the blocks: the list floats.
          _floating = c.maxWidth < _railWidth + _flyWidth + 380;
          final docked = !_floating && widget.palette;
          final showFloat = _floating && _floatOpen;
          return Row(
            children: [
              _palette(docked),
              const VerticalDivider(width: 1),
              Expanded(
                child: Stack(
                  children: [
                    _canvas(),
                    if (_error != null)
                      Positioned(top: 0, left: 0, right: 0, child: _errorBanner()),
                    if (showFloat)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: _flyWidth,
                        // Kept in the tree while dragging (the drag goes on),
                        // but out of the way of the drop places.
                        child: Offstage(
                          offstage: _dragging != null,
                          child: Material(
                            elevation: 10,
                            color: const Color(0xFF1B1D23),
                            child: _flyout(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static List<BNode> _snippet(String code) => _snippets.putIfAbsent(code, () {
    try {
      return parseSnippet(code);
    } on Object {
      return const [];
    }
  });

  static const _hTitle = TextStyle(fontWeight: FontWeight.w700, color: Colors.white);
  static const _hMuted = TextStyle(color: _muted);
  static final _hCode = codeStyle.copyWith(fontSize: 12.5, height: 1.4, color: _accent);
}
