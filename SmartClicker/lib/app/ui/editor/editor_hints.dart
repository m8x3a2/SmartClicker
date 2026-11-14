// Hints of the editor: suggestions while typing, parameters inside brackets,
// explanations and pictures under the mouse.
part of 'code_editor.dart';

/// The picture name under column [col] of [line]: the quoted first
/// argument of a picture function, e.g. `click_image("старт")`.
({String name, int start})? pictureNameAt(String line, int col) {
  for (final m in RegExp(r'''([A-Za-z_]\w*)\s*\(\s*(["'])([^"'\\]*)\2''').allMatches(line)) {
    final quote = m.start + m[0]!.length - m[3]!.length - 2;
    if (col < quote || col >= m.end) continue;
    if (!pictureFunctions.contains(m[1]) || m[3]!.trim().isEmpty) return null;
    return (name: m[3]!, start: quote);
  }
  return null;
}

/// Width and height from the header of a PNG file, or null.
({int w, int h})? pngSize(Uint8List b) {
  if (b.length < 24 || b[1] != 0x50 || b[2] != 0x4E || b[3] != 0x47) return null;
  int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (w: be(16), h: be(20));
}

extension _CodeEditorStateEditorHints on _CodeEditorState {
  void _hideAssist() {
    _hoverWord = null;
    _picture = null;
    if (_portal.isShowing) _portal.hide();
  }

  void _showPicture(String name, int anchorOffset) {
    final path = widget.imagePath!(name);
    Uint8List? bytes;
    var w = 0, h = 0;
    try {
      final f = File(path);
      if (f.existsSync()) {
        bytes = f.readAsBytesSync();
        final size = pngSize(bytes);
        if (size == null) {
          bytes = null;
        } else {
          (w, h) = (size.w, size.h);
        }
      }
    } catch (_) {
      bytes = null;
    }
    _showAssist(const [], false, anchorOffset);
    _picture = (name: name, path: path, bytes: bytes, w: w, h: h);
    if (_portal.isShowing) _setState(() {});
  }

  Widget _pictureOverlay(BuildContext context) {
    final p = _picture!;
    final screen = MediaQuery.sizeOf(context);
    const maxW = 360.0, maxH = 220.0;
    double dw = 0, dh = 0;
    if (p.bytes != null && p.w > 0 && p.h > 0) {
      // Small pictures are enlarged (up to 4x, crisp pixels), big ones shrunk.
      final k = math.min(4.0, math.min(maxW / p.w, maxH / p.h));
      dw = p.w * k;
      dh = p.h * k;
    }
    final width = p.bytes == null ? 380.0 : math.max(240.0, dw + 24);
    final height = p.bytes == null ? 62.0 : dh + 50;
    final left = _anchor.dx
        .clamp(8.0, math.max(8.0, screen.width - width - 8))
        .toDouble();
    final above = _anchor.dy - height - 4;
    final top = above > 8 ? above : _anchor.dy + _lineHeight + 4;
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Material(
          elevation: 8,
          color: const Color(0xFF262A33),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xFF3B4254)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: p.bytes == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Картинки «${p.name}» нет',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFFF7B72))),
                      const Text('Вырежьте её: Инструменты → Выделить область',
                          style: TextStyle(fontSize: 12, color: _muted)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.name}  ·  ${p.w}×${p.h}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: codeStyle.copyWith(
                              fontSize: 13,
                              height: 1.3,
                              color: const Color(0xFF6CB6FF))),
                      const SizedBox(height: 6),
                      Container(
                        // Checkerboard-like backdrop shows transparent parts.
                        color: const Color(0xFF14161B),
                        child: Image.memory(p.bytes!,
                            width: dw,
                            height: dh,
                            fit: BoxFit.fill,
                            filterQuality: dw > p.w
                                ? FilterQuality.none
                                : FilterQuality.medium,
                            gaplessPlayback: true),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _onHover(PointerHoverEvent e) {
    if (!widget.hoverHints || (_portal.isShowing && _isList)) return;
    final text = widget.controller.text;
    final lineNo = (e.localPosition.dy / _lineHeight).floor();
    final col = (e.localPosition.dx / _charW).floor();
    final lines = text.split('\n');
    Completion? hint;
    String? picture;
    var start = 0;
    if (lineNo >= 0 && lineNo < lines.length && widget.imagePath != null) {
      final pic = pictureNameAt(lines[lineNo], col);
      if (pic != null) {
        picture = pic.name;
        start = pic.start;
      }
    }
    if (picture == null && lineNo >= 0 && lineNo < lines.length) {
      final line = lines[lineNo];
      for (final m in _CodeEditorState._ident.allMatches(line)) {
        if (col < m.start || col >= m.end) continue;
        final name = m[0]!;
        final rest = line.substring(m.end).trimLeft();
        final param = paramHints[name];
        if (param != null && rest.startsWith(':')) {
          hint = Completion(name, '$name:', param);
        } else if (rest.startsWith('(')) {
          hint = completionFor(name, scriptFunctions(text));
        }
        start = m.start;
        break;
      }
    }
    final id = picture != null
        ? 'img:$lineNo:$start'
        : (hint == null ? null : '$lineNo:$start');
    if (id == _hoverWord && id != null) return;
    _hoverTimer?.cancel();
    if (_hoverWord != null) _hideAssist();
    if (hint == null && picture == null) return;
    final shown = hint;
    var offset = start;
    for (var i = 0; i < lineNo; i++) {
      offset += lines[i].length + 1;
    }
    _hoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (picture != null) {
        _showPicture(picture, offset);
      } else {
        _showAssist([shown!], false, offset);
      }
      _hoverWord = id;
    });
  }

  void _onHoverExit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    if (_hoverWord != null) _hideAssist();
  }

  void _showAssist(List<Completion> items, bool list, int anchorOffset) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return _hideAssist();
    final at = _lineCol(anchorOffset);
    _anchor = box.localToGlobal(Offset(at.col * _charW, at.line * _lineHeight));
    _items = items;
    _isList = list;
    _index = 0;
    if (_portal.isShowing) {
      _setState(() {});
    } else {
      _portal.show();
    }
  }

  void _computeAssist() {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid || !sel.isCollapsed) return _hideAssist();
    final text = c.text;
    final caret = sel.start;
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final line = text.substring(lineStart, caret);
    final inside = _lineContext(line);
    if (inside == _Inside.comment) return _hideAssist();
    final own = scriptFunctions(text);

    // 1. An identifier is being typed: list of names.
    final word = inside == _Inside.code ? _CodeEditorState._wordAtEnd.firstMatch(line) : null;
    if (word != null &&
        word.end - word.start >= 2 &&
        !(word.start > 0 && line[word.start - 1] == '.')) {
      final found = suggest(word[0]!, own);
      if (found.isNotEmpty) {
        _wordStart = lineStart + word.start;
        return _showAssist(found, true, _wordStart);
      }
    }

    // 2. The caret is inside the brackets of a known function: its signature.
    var depth = 0;
    for (var i = line.length - 1; i >= 0; i--) {
      final ch = line[i];
      if (ch == ')') {
        depth++;
      } else if (ch == '(') {
        if (depth > 0) {
          depth--;
          continue;
        }
        final name = _CodeEditorState._wordAtEnd.firstMatch(line.substring(0, i));
        final fn = name == null ? null : completionFor(name[0]!, own);
        if (fn != null && !fn.signature.endsWith('()')) {
          return _showAssist([fn], false, lineStart + name!.start);
        }
        break;
      }
    }
    _hideAssist();
  }

  void _accept(Completion c) {
    final ctl = widget.controller;
    final text = ctl.text;
    final caret = ctl.selection.start;
    if (caret < _wordStart || caret > text.length) return _hideAssist();
    final lineStart =
        _wordStart == 0 ? 0 : text.lastIndexOf('\n', _wordStart - 1) + 1;
    final indent =
        _CodeEditorState._indentRe.stringMatch(text.substring(lineStart, _wordStart)) ?? '';
    var ins = c.insert.replaceAll('\n', '\n$indent');
    // The brackets are already there: only the name is needed.
    if (c.isFunction && caret < text.length && text[caret] == '(') ins = c.name;
    var mark = ins.indexOf('|');
    if (mark < 0) {
      mark = ins.length;
    } else {
      ins = ins.replaceFirst('|', '');
    }
    ctl.value = TextEditingValue(
      text: text.replaceRange(_wordStart, caret, ins),
      selection: TextSelection.collapsed(offset: _wordStart + mark),
    );
  }

  Widget _assistOverlay(BuildContext context) {
    if (_picture != null) return _pictureOverlay(context);
    if (_items.isEmpty) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(520.0, screen.width - 16);
    final shown = math.min(_items.length, _CodeEditorState._maxItems);
    final height = _isList ? shown * _CodeEditorState._itemHeight + 8 : 62.0;
    final left = _anchor.dx
        .clamp(8.0, math.max(8.0, screen.width - width - 8))
        .toDouble();
    final below = _anchor.dy + _lineHeight + 2;
    final above = _anchor.dy - height - 2;
    // The list opens below the line, the signature hint above it.
    final double top;
    if (_isList) {
      top = below + height > screen.height - 8 && above > 8 ? above : below;
    } else {
      top = above > 8 ? above : below;
    }
    final first = (_index - shown + 1).clamp(0, _items.length - shown);

    Widget entry(Completion c, bool selected, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Container(
            height: _isList ? _CodeEditorState._itemHeight : null,
            color: selected ? const Color(0xFF33466B) : null,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: _isList
                ? Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: width * 0.6),
                        child: Text(c.signature,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: codeStyle.copyWith(
                                fontSize: 13,
                                height: 1.2,
                                color: const Color(0xFF6CB6FF))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(c.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: _muted)),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.signature,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: codeStyle.copyWith(
                              fontSize: 13,
                              height: 1.3,
                              color: const Color(0xFF6CB6FF))),
                      Text(c.hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, height: 1.25, color: _muted)),
                    ],
                  ),
          ),
        );

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: TextFieldTapRegion(
        child: Material(
          elevation: 8,
          color: const Color(0xFF262A33),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xFF3B4254)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _isList
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (var i = first; i < first + shown; i++)
                        entry(_items[i], i == _index,
                            onTap: () => _accept(_items[i])),
                    ],
                  ),
                )
              : IgnorePointer(child: entry(_items.first, false)),
        ),
      ),
    );
  }
}
