// Clipboard history (the «Буфер» page): what is copied is remembered (when
// switched on), any item goes back into the clipboard or is pasted into the
// window that was active before; several at once, or one by one with the
// hotkey. Storage — core/storage/clip_history.dart.
part of 'app_controller.dart';

/// PNG of a copied picture — in an isolate (a big screenshot takes a while).
Uint8List _clipPng(int w, int h, Uint8List bgra) => pngEncode(Bitmap(w, h, bgra));

extension AppControllerClipboard on AppController {
  ClipHistory get clips => _clips ??= (ClipHistory(paths.clipboard)..load());

  int get _clipMaxBytes => settings.clipMaxMb * 1024 * 1024;

  /// Called from the poll twice a second.
  void _checkClipboard() {
    if (!settings.clipHistory || _clipReading) return;
    final seq = backend.clipboardSequence();
    if (seq == _clipSeq) return;
    // Right after the start (or switching on) only what is copied from now
    // on counts: what lies in the clipboard may be an item already pasted
    // and moved to the trash.
    if (_clipSeq == -1) {
      _clipSeq = seq;
      return;
    }
    final data = backend.readClipboard();
    if (data == null) return; // busy: next time
    _clipSeq = seq;
    if (data.private || data.isEmpty) return;
    final now = DateTime.now();
    final id = ClipHistory.newId();
    if (data.text != null) {
      if (data.text!.trim().isEmpty) return;
      _addClip(ClipItem(
          id: id, kind: 'text', text: data.text, bytes: utf8.encode(data.text!).length, at: now));
    } else if (data.files != null) {
      _addClip(ClipItem(id: id, kind: 'files', files: data.files, bytes: 0, at: now));
    } else if (data.image != null) {
      final img = data.image!;
      _clipReading = true;
      Isolate.run(() => _clipPng(img.w, img.h, img.bgra)).then((png) {
        final name = '$id.png';
        Directory(paths.clipboard).createSync(recursive: true);
        File('${paths.clipboard}${Platform.pathSeparator}$name').writeAsBytesSync(png);
        _addClip(ClipItem(
            id: id, kind: 'image', image: name, w: img.w, h: img.h, bytes: png.length, at: now));
      }).catchError((Object e, StackTrace s) {
        ErrorJournal.record(e, s, where: 'clipboard picture');
      }).whenComplete(() => _clipReading = false);
    }
  }

  void _addClip(ClipItem item) {
    clips.add(item, maxItems: settings.clipMaxItems, maxBytes: _clipMaxBytes);
    clipVersion.value++;
  }

  /// Turns the history on/off (on: what is in the clipboard now is the first).
  void setClipHistory(bool on) {
    settings.clipHistory = on;
    _clipSeq = -1;
    saveSettings();
    _changed();
  }

  /// New limits: the oldest unpinned items go at once.
  void setClipLimits({int? items, int? mb}) {
    if (items != null) settings.clipMaxItems = items.clamp(1, 5000);
    if (mb != null) settings.clipMaxMb = mb.clamp(1, 2000);
    saveSettings();
    clips.trim(maxItems: settings.clipMaxItems, maxBytes: _clipMaxBytes);
    clips.save();
    clipVersion.value++;
  }

  void togglePinClip(ClipItem i) {
    i.pinned = !i.pinned;
    clips.save();
    clipVersion.value++;
  }

  void removeClips(Iterable<ClipItem> items) {
    for (final i in items.toList()) {
      clips.remove(i);
    }
    clipQueue.removeWhere((q) => !clips.items.contains(q));
    clipVersion.value++;
  }

  void clearClips() {
    clips.clear();
    clipQueue.removeWhere((q) => !clips.items.contains(q));
    clipVersion.value++;
  }

  /// Puts [i] back into the clipboard. False — the system clipboard is busy.
  bool copyClip(ClipItem i) {
    try {
      switch (i.kind) {
        case 'files':
          return backend.setClipboardFiles(i.files!) && _ownClip();
        case 'image':
          final b = pngDecode(File(clips.imagePath(i)).readAsBytesSync());
          return backend.setClipboardImage(b.w, b.h, b.bgra) && _ownClip();
        default:
          backend.setClipboard(i.text!);
          return _ownClip();
      }
    } catch (e) {
      notify('Буфер обмена', 'Не получилось: $e', level: 'warn');
      return false;
    }
  }

  /// What we put into the clipboard ourselves is not a new copy.
  bool _ownClip() {
    _clipSeq = backend.clipboardSequence();
    return true;
  }

  /// The window the history hotkey was pressed in: items are pasted there.
  WindowInfo? get clipTarget => _clipTarget;

  /// Pastes [i] into the window that was active before (or just puts it into
  /// the clipboard when there is none).
  Future<void> pasteClip(ClipItem i) async {
    if (!copyClip(i)) return;
    // Used again: on top of the history, as if copied now.
    if (clips.items.remove(i)) {
      clips.items.insert(0, i);
      clips.save();
      clipVersion.value++;
    }
    await _pasteInto(_clipTarget, 'Скопировано: ${_short(i.title)}');
  }

  /// Several items at once: texts joined by lines; with files or pictures —
  /// everything as files (texts as .txt), Ctrl+V pastes them all.
  Future<void> pasteClipsAtOnce(List<ClipItem> items) async {
    if (items.isEmpty) return;
    final ok = items.every((i) => i.kind == 'text')
        ? _setText(items.map((i) => i.text!).join('\n'))
        : backend.setClipboardFiles([for (final i in items) ..._asFiles(i)]);
    if (!ok) return;
    await _pasteInto(_clipTarget, 'В буфере ${items.length} шт. — вставьте Ctrl+V');
  }

  bool _setText(String t) {
    backend.setClipboard(t);
    return true;
  }

  List<String> _asFiles(ClipItem i) => switch (i.kind) {
        'files' => i.files!,
        'image' => [clips.imagePath(i)],
        _ => [_textFile(i)],
      };

  String _textFile(ClipItem i) {
    final p = '${paths.clipboard}${Platform.pathSeparator}текст-${i.id}.txt';
    File(p).writeAsStringSync(i.text!);
    return p;
  }

  Future<void> _pasteInto(WindowInfo? target, String noTarget) async {
    _clipTarget = null;
    if (target == null || !backend.focusWindow(target.handle)) {
      notify('Буфер обмена', noTarget, level: 'ok');
      _changed();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    // The hotkey (Win+Alt+V) may still be held: Ctrl+V together with them
    // is not "paste". Wait until the user lets go (not longer than 2 s).
    const mods = [0x10, 0x11, 0x12, 0x5B, 0x5C, 0x56];
    for (var i = 0; i < 40 && mods.any(backend.isUserKeyDown); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    backend.keyEvent('ctrl', true);
    backend.keyEvent('v', true);
    backend.keyEvent('v', false);
    backend.keyEvent('ctrl', false);
    _changed();
  }

  /// "One by one": every press of the history hotkey pastes the next of
  /// [items] into the active window.
  void startClipQueue(List<ClipItem> items) {
    clipQueue
      ..clear()
      ..addAll(items);
    clipQueueTotal = items.length;
    notify('Очередь вставки',
        '${items.length} шт.: в нужном окне жмите ${settings.clipKey.toUpperCase()} — вставится следующий',
        level: 'ok');
    _changed();
  }

  void stopClipQueue() {
    clipQueue.clear();
    _changed();
  }

  /// The history hotkey: the next item of the queue into the active window,
  /// or the «Буфер» page over it (an item clicked there is pasted back).
  Future<void> _onClipHotkey() async {
    final active = backend.activeWindow();
    final mine = active != null && active.pid == pid; // this process
    if (clipQueue.isNotEmpty && !mine) {
      final next = clipQueue.removeAt(0);
      if (!copyClip(next)) return;
      await _pasteInto(active, '');
      _trashPasted(next);
      final left = clipQueue.length;
      notify('Очередь вставки',
          left == 0 ? 'Вставлено всё ($clipQueueTotal)' : 'Вставлено ${clipQueueTotal - left} из $clipQueueTotal');
      return;
    }
    // "One by one": the oldest item is pasted and goes to the trash.
    if (settings.clipOneByOne && !mine) {
      final next = clips.nextInLine;
      if (next == null) {
        notify('Буфер по очереди', 'Вставлять нечего — история пуста', level: 'warn');
        return;
      }
      if (!copyClip(next)) return;
      await _pasteInto(active, '');
      _trashPasted(next);
      final left = clips.items.where((i) => !i.pinned).length;
      notify('Буфер по очереди', 'Вставлено: ${_short(next.title)}. Осталось $left');
      return;
    }
    _clipTarget = mine ? _clipTarget : active;
    if (compact) setCompact(false);
    restoreFromTray();
    backend.activateSelf();
    openPage('clipboard');
    _changed();
  }

  void _trashPasted(ClipItem i) {
    clips.toTrash(i);
    clipVersion.value++;
  }

  void setClipOneByOne(bool on) {
    settings.clipOneByOne = on;
    saveSettings();
    _changed();
  }

  void restoreClip(ClipItem i) {
    clips.restore(i);
    clipVersion.value++;
  }

  void emptyClipTrash() {
    clips.emptyTrash();
    clipVersion.value++;
  }

  static String _short(String s) => s.length > 60 ? '${s.substring(0, 60)}…' : s;
}
