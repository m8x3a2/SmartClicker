// Editable text inside a slot, a comment or a code block.
part of 'blocks_editor.dart';

/// Editable value of a slot. While it has the keyboard it keeps its look
/// and text even if the value becomes another kind (a call, a number).
class _SlotField extends StatefulWidget {
  final _BlocksEditorState ed;
  final String id;
  final String src;

  /// Edits the text of a string literal (without quotes).
  final bool textMode;
  final _Look look;
  final Color? swatch;
  final String placeholder;

  /// Extra check of the text (names); expressions are always checked.
  final bool Function(String)? validate;
  final ValueChanged<String> onChanged;
  const _SlotField({
    super.key,
    required this.ed,
    required this.id,
    required this.src,
    required this.textMode,
    required this.look,
    required this.onChanged,
    this.swatch,
    this.placeholder = '',
    this.validate,
  });

  @override
  State<_SlotField> createState() => _SlotFieldState();
}

class _SlotFieldState extends State<_SlotField> {
  final _c = TextEditingController();
  final _f = FocusNode();
  late bool _text = widget.textMode;
  bool _bad = false;

  String _shown(String src) {
    if (!_text) return src;
    final s = shapeOf(src);
    return s is XStr ? s.value : (s is XEmpty ? '' : src);
  }

  @override
  void initState() {
    super.initState();
    _c.text = _shown(widget.src);
    _f.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_SlotField old) {
    super.didUpdateWidget(old);
    if (_f.hasFocus) return;
    _text = widget.textMode;
    final s = _shown(widget.src);
    if (_c.text != s) _c.text = s;
    _bad = false;
  }

  void _onFocus() {
    final ed = widget.ed;
    if (_f.hasFocus) {
      ed._editingSlot = widget.id;
      ed._lastSlot = _SlotRef(widget.id, widget.onChanged);
    } else {
      if (ed._editingSlot == widget.id) ed._editingSlot = null;
      if (_bad) {
        _c.text = _shown(widget.src);
        _bad = false;
      }
      _text = widget.textMode;
      if (ed.mounted) ed.setState(() {});
    }
  }

  @override
  void dispose() {
    if (widget.ed._editingSlot == widget.id && _f.hasFocus) widget.ed._editingSlot = null;
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    final String code;
    if (_text) {
      code = quote(v);
    } else {
      final t = v.trim();
      final ok = widget.validate != null ? widget.validate!(t) : isValidExpr(t);
      if (!ok) {
        if (!_bad) setState(() => _bad = true);
        return;
      }
      code = t;
    }
    if (_bad) setState(() => _bad = false);
    widget.onChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final look = _bad ? _Look.bad : widget.look;
    final multi = _c.text.contains('\n');
    return Container(
      constraints: const BoxConstraints(minWidth: 24, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: look.decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.swatch != null && _text) ...[
            _swatch(widget.swatch!),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: IntrinsicWidth(
              child: TextField(
                controller: _c,
                focusNode: _f,
                onChanged: _changed,
                style: look.style,
                maxLines: multi ? null : 1,
                contextMenuBuilder: null,
                cursorColor: look == _Look.literal ? const Color(0xFF1E2128) : Colors.white,
                cursorHeight: 15,
                decoration: InputDecoration.collapsed(
                  hintText: widget.placeholder.isEmpty ? '…' : widget.placeholder,
                  hintStyle: look.style.copyWith(color: look.style.color?.withValues(alpha: 0.45)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text of a comment or a code block. [live] — every change is written;
/// otherwise the text is written when the field loses the keyboard (and
/// only if [validate] has no complaints).
class _TextArea extends StatefulWidget {
  final _BlocksEditorState ed;
  final String id;
  final String text;
  final TextStyle style;
  final bool live;
  final String? Function(String)? validate;
  final ValueChanged<String> onCommit;
  const _TextArea({
    super.key,
    required this.ed,
    required this.id,
    required this.text,
    required this.style,
    required this.live,
    required this.onCommit,
    this.validate,
  });

  @override
  State<_TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<_TextArea> {
  late final _c = TextEditingController(text: widget.text);
  final _f = FocusNode();
  String? _err;

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      final ed = widget.ed;
      if (_f.hasFocus) {
        ed._editingSlot = widget.id;
        return;
      }
      if (ed._editingSlot == widget.id) ed._editingSlot = null;
      if (!widget.live) _commit();
    });
  }

  @override
  void didUpdateWidget(_TextArea old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.text) {
      _c.text = widget.text;
      _err = null;
    }
  }

  @override
  void dispose() {
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _c.text;
    if (v == widget.text) {
      if (_err != null) setState(() => _err = null);
      return;
    }
    final err = widget.validate?.call(v);
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    setState(() => _err = null);
    widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) {
    final field = IntrinsicWidth(
      child: TextField(
        controller: _c,
        focusNode: _f,
        maxLines: null,
        contextMenuBuilder: null,
        style: widget.style,
        cursorColor: Colors.white,
        onChanged: widget.live ? (_) => _commit() : null,
        decoration: const InputDecoration.collapsed(hintText: '…'),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, maxWidth: 620),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _f.unfocus(),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _c.text = widget.text;
            _err = null;
            _f.unfocus();
          },
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            field,
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Ошибка: $_err (Esc — отменить правку)',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFFF7B72)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- drop places
