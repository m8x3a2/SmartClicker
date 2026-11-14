// Code editor: line numbers, breakpoints, current and error lines, keys.
// Parts: code_controller (colours), editor_hints, editor_search.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/lang/completions.dart';
import '../../../core/lang/picture_refs.dart';

part 'code_controller.dart';
part 'editor_hints.dart';
part 'editor_search.dart';

const _fontSize = 14.0;

const _lineHeight = 21.0; // _fontSize * 1.5

const _topPad = 8.0;

const _muted = Color(0xFF8B92A1);

const codeStyle = TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: ['Courier New', 'monospace'],
  fontSize: _fontSize,
  height: 1.5,
  color: Color(0xFFD7DAE0),
);

const _strut = StrutStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: ['Courier New', 'monospace'],
  fontSize: _fontSize,
  height: 1.5,
  forceStrutHeight: true,
);

class CodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final ValueListenable<int> currentLine;
  final ValueListenable<int> errorLine;
  final bool readOnly;

  /// Every change of this value opens the search bar (menu command).
  final ValueListenable<int>? findRequest;

  /// Suggest function names while typing / explain them under the mouse.
  final bool suggestions;
  final bool hoverHints;

  /// Read-only text viewer (help pages): no line numbers, the search bar
  /// is always there.
  final bool viewer;

  /// Breakpoints (red dots on line numbers); a click on a number calls
  /// [onBreakpoint].
  final ValueListenable<Set<int>>? breakpoints;
  final void Function(int line)? onBreakpoint;

  /// Full path of a picture by its name in the script; with it, the
  /// picture is shown when the mouse is over its name.
  final String Function(String name)? imagePath;

  /// A line to show (puts the cursor there); the editor sets it back to 0.
  final ValueNotifier<int>? revealLine;

  /// Own undo / redo (Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z): the history of the
  /// script lives outside the widget. Without them the built-in one works.
  final VoidCallback? onUndo, onRedo;
  const CodeEditor({
    super.key,
    required this.controller,
    required this.currentLine,
    required this.errorLine,
    this.readOnly = false,
    this.findRequest,
    this.suggestions = true,
    this.hoverHints = true,
    this.viewer = false,
    this.breakpoints,
    this.onBreakpoint,
    this.imagePath,
    this.revealLine,
    this.onUndo,
    this.onRedo,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _v = ScrollController();
  final _h = ScrollController();
  final _lines = ValueNotifier<int>(1);
  final _editorFocus = FocusNode();
  final _stackKey = GlobalKey();
  double? _charWidth;

  // Search bar
  bool _findOpen = false;
  bool _replaceOpen = false;
  String _findInfo = '';
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _findFocus = FocusNode();

  // Suggestions / signature hint
  final _portal = OverlayPortalController();
  List<Completion> _items = const [];
  int _index = 0;
  bool _isList = false;
  int _wordStart = 0;
  Offset _anchor = Offset.zero;
  String _lastText = '';

  static const _itemHeight = 28.0;
  static const _maxItems = 7;
  static final _wordAtEnd = RegExp(r'[A-Za-z_]\w*$');
  static final _indentRe = RegExp(r'^[ \t]*');

  CodeController? get _code {
    final c = widget.controller;
    return c is CodeController ? c : null;
  }

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onChanged);
    widget.currentLine.addListener(_follow);
    widget.findRequest?.addListener(_openFind);
    widget.revealLine?.addListener(_revealRequested);
    // Opened for "where used": the request came before this editor existed.
    if ((widget.revealLine?.value ?? 0) > 0) _revealRequested();
    _editorFocus.addListener(_onFocus);
    _v.addListener(_hideAssist);
    _h.addListener(_hideAssist);
    _countLines();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.currentLine.removeListener(_follow);
    widget.findRequest?.removeListener(_openFind);
    widget.revealLine?.removeListener(_revealRequested);
    // The controller outlives the editor: do not leave highlights behind.
    final code = _code;
    if (code != null && code._query.isNotEmpty) {
      code._query = '';
      code._active = -1;
    }
    _hoverTimer?.cancel();
    _editorFocus.dispose();
    _findFocus.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  void _countLines() =>
      _lines.value = '\n'.allMatches(widget.controller.text).length + 1;

  double get _charW => _charWidth ??= () {
        final p = TextPainter(
          text: const TextSpan(text: 'MMMMMMMMMM', style: codeStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = p.width / 10;
        p.dispose();
        return w;
      }();

  void _onChanged() {
    _countLines();
    final text = widget.controller.text;
    final typed = text != _lastText;
    _lastText = text;
    if (!typed ||
        widget.readOnly ||
        !widget.suggestions ||
        !_editorFocus.hasFocus) {
      _hideAssist();
    } else {
      _computeAssist();
    }
    if (_findOpen) setState(() {}); // match counter
  }

  void _onFocus() {
    if (!_editorFocus.hasFocus) _hideAssist();
  }

  /// Puts the cursor on the requested line and scrolls to it (after the
  /// frame: when another script was opened, this editor may be on its way out).
  void _revealRequested() {
    final line = widget.revealLine?.value ?? 0;
    if (line <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.revealLine?.value != line) return;
      widget.revealLine!.value = 0;
      final text = widget.controller.text;
      var offset = 0;
      for (var l = 1; l < line; l++) {
        final nl = text.indexOf('\n', offset);
        if (nl < 0) break;
        offset = nl + 1;
      }
      widget.controller.selection = TextSelection.collapsed(offset: offset);
      _editorFocus.requestFocus();
      _reveal(offset, center: true);
    });
  }

  /// Keeps the executing line visible while a script runs.
  void _follow() {
    final line = widget.currentLine.value;
    if (line <= 0 || !_v.hasClients) return;
    final y = (line - 1) * _lineHeight;
    final top = _v.offset, bottom = top + _v.position.viewportDimension;
    if (y < top + _lineHeight || y > bottom - 3 * _lineHeight) {
      final target = (y - _v.position.viewportDimension / 3)
          .clamp(0.0, _v.position.maxScrollExtent);
      _v.jumpTo(target);
    }
  }

  ({int line, int col}) _lineCol(int offset) {
    final text = widget.controller.text;
    final o = offset.clamp(0, text.length);
    final before = text.substring(0, o);
    return (
      line: '\n'.allMatches(before).length,
      col: o - (before.lastIndexOf('\n') + 1)
    );
  }

  /// Scrolls so that a text position is visible (after the next layout).
  void _reveal(int offset, {bool center = false}) {
    final at = _lineCol(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_v.hasClients) {
        final y = _topPad + at.line * _lineHeight;
        final top = _v.offset, view = _v.position.viewportDimension;
        final max = _v.position.maxScrollExtent;
        if (y < top + (center ? _lineHeight : 0) ||
            y + _lineHeight > top + view - (center ? 2 * _lineHeight : 0)) {
          final target = center
              ? y - view / 3
              : (y < top ? y - _lineHeight : y + 2 * _lineHeight - view);
          _v.jumpTo(target.clamp(0.0, max));
        }
      }
      if (_h.hasClients) {
        final x = at.col * _charW;
        final left = _h.offset, view = _h.position.viewportDimension;
        if (x < left + 20 || x > left + view - 60) {
          _h.jumpTo((x - view / 2).clamp(0.0, _h.position.maxScrollExtent));
        }
      }
    });
  }

  /// The picture shown under the mouse (instead of a text hint).
  ({String name, String path, Uint8List? bytes, int w, int h})? _picture;

  // Hint under the mouse: a function name or a named argument.
  Timer? _hoverTimer;
  String? _hoverWord;
  static final _ident = RegExp(r'[A-Za-z_]\w*');

  // -------------------------------------------------------------------- keys

  void _insert(String text, {int? caretBack}) {
    final c = widget.controller;
    final sel = c.selection;
    final at = sel.start + text.length - (caretBack ?? 0);
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(offset: at),
    );
    _reveal(at);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final plain = !kb.isControlPressed && !kb.isAltPressed && !kb.isMetaPressed;
    final enter =
        key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

    if (_portal.isShowing) {
      if (key == LogicalKeyboardKey.escape) {
        _hideAssist();
        return KeyEventResult.handled;
      }
      if (_isList && plain && !kb.isShiftPressed && _items.isNotEmpty) {
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          final d = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
          setState(() => _index = (_index + d) % _items.length);
          return KeyEventResult.handled;
        }
        if (enter || key == LogicalKeyboardKey.tab) {
          _accept(_items[_index]);
          return KeyEventResult.handled;
        }
      }
    } else if (key == LogicalKeyboardKey.escape && _findOpen) {
      _closeFind();
      return KeyEventResult.handled;
    }

    final c = widget.controller;
    final sel = c.selection;
    if (widget.readOnly || !plain || kb.isShiftPressed || !sel.isValid) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      _insert('    ');
      return KeyEventResult.handled;
    }
    if (enter) {
      // New line keeps the indentation; after "{" it goes one level deeper.
      final text = c.text;
      final lineStart =
          sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
      final before = text.substring(lineStart, sel.start);
      final indent = _indentRe.stringMatch(before) ?? '';
      final opens = before.trimRight().endsWith('{');
      final closes = sel.end < text.length && text[sel.end] == '}';
      if (opens && closes) {
        _insert('\n$indent    \n$indent', caretBack: indent.length + 1);
      } else {
        _insert('\n$indent${opens ? '    ' : ''}');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------- build

  Widget _marker(ValueListenable<int> line, Color color) => Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<int>(
            valueListenable: line,
            builder: (_, l, _) => l <= 0
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: (l - 1) * _lineHeight),
                      child: Container(height: _lineHeight, color: color),
                    ),
                  ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            _openFind(replace: true),
        const SingleActivator(LogicalKeyboardKey.f3): () => _stepFind(1),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
            _stepFind(-1),
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _assistOverlay,
        child: Container(
          color: const Color(0xFF1B1D23),
          child: Stack(
            children: [
              Positioned.fill(child: _scrollArea()),
              if (_findOpen)
                Positioned(top: 6, right: 18, child: _findBar())
              else if (widget.viewer)
                Positioned(
                  top: 6,
                  right: 18,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.search, size: 18),
                    tooltip: 'Поиск (Ctrl+F)',
                    onPressed: _openFind,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static final _noBreaks = ValueNotifier<Set<int>>(const {});

  /// Line numbers; a click on one sets or removes a breakpoint.
  Widget _gutter() {
    final click = widget.onBreakpoint;
    return SizedBox(
      width: 48,
      child: ValueListenableBuilder<int>(
        valueListenable: _lines,
        builder: (_, n, _) => ValueListenableBuilder<Set<int>>(
          valueListenable: widget.breakpoints ?? _noBreaks,
          builder: (_, br, _) {
            final numbers = Stack(children: [
              SizedBox(
                width: 48,
                child: Text(
                  List.generate(n, (i) => '${i + 1}').join('\n'),
                  textAlign: TextAlign.right,
                  style: codeStyle.copyWith(color: const Color(0xFF555B69)),
                  strutStyle: _strut,
                ),
              ),
              for (final l in br)
                if (l <= n)
                  Positioned(
                    left: 2,
                    top: (l - 1) * _lineHeight + (_lineHeight - 11) / 2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: const BoxDecoration(
                          color: Color(0xFFE5484D), shape: BoxShape.circle),
                    ),
                  ),
            ]);
            if (click == null) return numbers;
            return Tooltip(
              message: 'Щелчок по номеру строки — точка останова: скрипт '
                  'остановится перед этой строкой',
              waitDuration: const Duration(milliseconds: 1200),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final line = (d.localPosition.dy / _lineHeight).floor() + 1;
                    if (line >= 1 && line <= n) click(line);
                  },
                  child: numbers,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _scrollArea() {
    return Scrollbar(
      controller: _v,
      child: SingleChildScrollView(
        controller: _v,
        padding: const EdgeInsets.symmetric(vertical: _topPad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.viewer) _gutter(),
            const SizedBox(width: 14),
            Expanded(
              child: SingleChildScrollView(
                controller: _h,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 3000,
                  child: Stack(
                    key: _stackKey,
                    children: [
                      _marker(widget.errorLine, const Color(0x55E5484D)),
                      _marker(widget.currentLine, const Color(0x443B82F6)),
                      MouseRegion(
                        opaque: false,
                        onHover: _onHover,
                        onExit: _onHoverExit,
                        child: Focus(
                        onKeyEvent: _onKey,
                        child: Actions(
                          // Own intents: the text field does not know them, so
                          // they reach these actions (its built-in undo would
                          // catch UndoTextIntent first).
                          actions: {
                            _OwnUndo: CallbackAction<_OwnUndo>(
                                onInvoke: (_) => widget.readOnly ? null : widget.onUndo?.call()),
                            _OwnRedo: CallbackAction<_OwnRedo>(
                                onInvoke: (_) => widget.readOnly ? null : widget.onRedo?.call()),
                          },
                          child: Shortcuts(
                          shortcuts: widget.onUndo != null
                              ? const {
                                  SingleActivator(LogicalKeyboardKey.keyY, control: true): _OwnRedo(),
                                  SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
                                      _OwnRedo(),
                                  SingleActivator(LogicalKeyboardKey.keyZ, control: true): _OwnUndo(),
                                }
                              : const {
                            // Redo: Ctrl+Y and Ctrl+Shift+Z.
                            SingleActivator(LogicalKeyboardKey.keyY, control: true):
                                RedoTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyZ,
                                    control: true, shift: true):
                                RedoTextIntent(SelectionChangedCause.keyboard),
                            SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                                UndoTextIntent(SelectionChangedCause.keyboard),
                          },
                          child: TextField(
                            controller: widget.controller,
                            focusNode: _editorFocus,
                            readOnly: widget.readOnly,
                            maxLines: null,
                            style: codeStyle,
                            strutStyle: _strut,
                            autocorrect: false,
                            enableSuggestions: false,
                            cursorColor: const Color(0xFF6CB6FF),
                            decoration:
                                const InputDecoration.collapsed(hintText: ''),
                          ),
                        ),
                        ),
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
    );
  }

  /// setState for the parts of the editor (extensions may not call it).
  void _setState(VoidCallback f) => setState(f);
}

/// Ctrl+Z / Ctrl+Y handled by the history of the script (see [CodeEditor.onUndo]).
class _OwnUndo extends Intent {
  const _OwnUndo();
}

class _OwnRedo extends Intent {
  const _OwnRedo();
}
