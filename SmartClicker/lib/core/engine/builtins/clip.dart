// Built-in functions: the clipboard history of the «Буфер» page
// (clip_history, copy_clip, paste_clip) and the script's own stack of things
// to paste — one by one (paste_next) or all at once (paste_all).
part of '../runtime.dart';

/// One thing of the script's stack: a text or a file.
class _StackItem {
  final String? text, file;
  const _StackItem.text(this.text) : file = null;
  const _StackItem.file(this.file) : text = null;
  String get title => file ?? (text!.length > 40 ? '${text!.substring(0, 40)}…' : text!);
}

extension ScriptRuntimeBuiltinsClip on ScriptRuntime {
  void _registerClip() {
    // The history: 1 — the newest copy. Each item: {n, kind, text, files,
    // image (path of the .png), time, pinned}.
    _def('clip_history', (c) {
      final items = _clipItems();
      return [for (var i = 0; i < items.length; i++) _clipValue(i + 1, items[i])];
    });

    // Item n of the history into the clipboard (without pasting).
    _def('copy_clip', (c) {
      final it = _clipItem(c, 'copy_clip');
      if (dryRun) {
        log('[тест] в буфер обмена: ${_clipTitle(it)}', 'action');
        return true;
      }
      _cancelClipboardRestore();
      return _putClip(c, it, 'copy_clip');
    });

    // Item n of the history pasted (Ctrl+V) into the active window.
    _def('paste_clip', (c) async {
      final it = _clipItem(c, 'paste_clip');
      await _pasteWith('вставка из истории буфера: ${_clipTitle(it)}', () => _putClip(c, it, 'paste_clip'));
      return true;
    });

    // The script's own stack.
    _def('clip_add', (c) {
      _clipStack.add(_StackItem.text(stringify(c.arg(0, 'text'))));
      return _clipStack.length;
    });
    _def('clip_add_file', (c) {
      final name = _s(c, c.arg(0, 'path'), 'clip_add_file');
      final path = _path(name);
      if (!File(path).existsSync() && !Directory(path).existsSync()) {
        c.fail('clip_add_file: нет файла "$name" (имя без пути — в папке files; снимок screenshot("имя") — "имя.png")');
      }
      _clipStack.add(_StackItem.file(path));
      return _clipStack.length;
    });
    _def('clip_count', (c) => _clipStack.length);
    _def('clip_clear', (c) {
      _clipStack.clear();
      return null;
    });

    // The first of the stack: pasted and taken out. false — the stack is empty.
    _def('paste_next', (c) async {
      if (_clipStack.isEmpty) return false;
      final it = _clipStack.removeAt(0);
      await _pasteWith('вставка из стопки: ${it.title} (осталось ${_clipStack.length})', () {
        if (it.file != null) return backend.setClipboardFiles([it.file!]);
        backend.setClipboard(it.text!);
        return true;
      });
      return true;
    });

    // Everything of the stack at once: texts joined (separator: "\n"); with
    // files — all as files (texts become .txt). The stack is emptied.
    _def('paste_all', (c) async {
      if (_clipStack.isEmpty) return false;
      final items = [..._clipStack];
      _clipStack.clear();
      final sep = c.opt('separator') == null ? '\n' : stringify(c.opt('separator'));
      final texts = items.every((i) => i.file == null);
      await _pasteWith('вставка всей стопки: ${items.length} шт.', () {
        if (texts) {
          backend.setClipboard(items.map((i) => i.text).join(sep));
          return true;
        }
        return backend.setClipboardFiles([for (final i in items) i.file ?? _textAsFile(i.text!)]);
      });
      return true;
    });
  }

  /// Puts something into the clipboard with [put] and presses Ctrl+V, as
  /// paste() does (the test mode only writes to the log).
  Future<void> _pasteWith(String description, bool Function() put) async {
    if (!await _guardInput(description)) return;
    _cancelClipboardRestore(); // the script manages the clipboard itself
    if (!put()) {
      log('Буфер обмена занят — не удалось положить: $description', 'warn');
      return;
    }
    await this.sleep(50, jitter: false);
    if (!_windowOk()) await _guardInput('восстановить окно для вставки');
    try {
      _key('ctrl', true);
      _key('v', true);
      await this.sleep(30, jitter: false);
    } finally {
      _key('v', false);
      _key('ctrl', false);
    }
  }

  String _textAsFile(String text) {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}smartclicker-clip')
      ..createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}текст-${DateTime.now().microsecondsSinceEpoch}.txt');
    f.writeAsStringSync(text);
    return f.path;
  }

  /// The items of the history (newest first), as the «Буфер» page keeps them.
  List<Map> _clipItems() {
    final dir = cfg['clipDir'] as String?;
    if (dir == null) return const [];
    try {
      final f = File('$dir${Platform.pathSeparator}index.json');
      if (!f.existsSync()) return const [];
      final d = jsonDecode(f.readAsStringSync());
      final list = d is Map ? d['items'] : d;
      return list is List ? list.whereType<Map>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Map _clipItem(CallCtx c, String fn) {
    final n = _n(c, c.arg(0, 'n') ?? 1, fn).round();
    final items = _clipItems();
    if (items.isEmpty) {
      c.fail('$fn: история буфера пуста (раздел «Буфер» → «Запоминать, что копирую»)');
    }
    if (n < 1 || n > items.length) c.fail('$fn($n): в истории ${items.length} записей (1 — самая новая)');
    return items[n - 1];
  }

  String _clipImagePath(Map it) =>
      '${cfg['clipDir']}${Platform.pathSeparator}${it['image']}';

  Map<String, Object?> _clipValue(int n, Map it) => {
        'n': n,
        'kind': '${it['kind']}',
        'text': it['text'],
        'files': it['files'],
        'image': it['image'] == null ? null : _clipImagePath(it),
        'time': it['at'],
        'pinned': it['pinned'] == true,
      };

  String _clipTitle(Map it) => switch ('${it['kind']}') {
        'files' => 'файлы (${(it['files'] as List? ?? const []).length})',
        'image' => 'картинка ${it['w']}×${it['h']}',
        _ => () {
            final t = '${it['text'] ?? ''}';
            return '"${t.length > 40 ? '${t.substring(0, 40)}…' : t}"';
          }(),
      };

  bool _putClip(CallCtx c, Map it, String fn) {
    switch ('${it['kind']}') {
      case 'files':
        return backend.setClipboardFiles([for (final f in (it['files'] as List? ?? const [])) '$f']);
      case 'image':
        final f = File(_clipImagePath(it));
        if (!f.existsSync()) c.fail('$fn: картинки этой записи уже нет на диске');
        final b = pngDecode(f.readAsBytesSync());
        return backend.setClipboardImage(b.w, b.h, b.bgra);
      default:
        backend.setClipboard('${it['text'] ?? ''}');
        return true;
    }
  }
}
