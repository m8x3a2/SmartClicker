// The "Pictures" page: cut a region of the screen, save pictures, check text
// recognition, ready commands.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';
import '../../services/ocr_install.dart';
import '../../../core/storage/storage.dart';
import '../../../core/vision/image.dart';
import '../../../core/vision/paddle_ocr.dart';
import '../../../core/vision/ocr.dart';
import '../editor/code_editor.dart';
import 'picture_actions.dart';

const _muted = Color(0xFF8B92A1);

String _paddleRead(String dir, int w, int h, Uint8List bgra) =>
    PaddleOcr.open(dir).read(Bitmap(w, h, bgra));

/// Top-level on purpose: the closure sent to the isolate must hold nothing
/// but these values.
Future<String> _paddleInIsolate(String dir, int w, int h, Uint8List bgra) =>
    Isolate.run(() => _paddleRead(dir, w, h, bgra));

/// "Pictures and text": shows what was just selected on the screen and the
/// saved picture samples; lets the user rename them, try the text
/// recognition and copy ready-made commands.
class VisionPage extends StatelessWidget {
  final AppController app;
  const VisionPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ScreenCapture?>(
        valueListenable: app.captured,
        // A new selection starts the page afresh.
        builder: (_, cap, _) => _Vision(app, cap, key: ObjectKey(cap)),
      );
}

class _Vision extends StatefulWidget {
  final AppController app;
  final ScreenCapture? capture;
  const _Vision(this.app, this.capture, {super.key});

  @override
  State<_Vision> createState() => _VisionState();
}

class _VisionState extends State<_Vision> {
  static const _fresh = '\u0000fresh';
  List<String> _names = [];
  String? _sel; // _fresh, a saved picture name or null
  Bitmap? _bitmap;
  Uint8List? _png;
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _want = TextEditingController();
  String? _nameError;
  String _text = '';
  String _ocrNote = '';
  bool _busy = false;
  int _job = 0;
  double? _install; // download progress
  String _installNote = '';

  AppController get app => widget.app;
  String get _dir => app.paths.files;
  String get _ocrDir => app.paths.ocr;
  File _file(String name) => File('$_dir${Platform.pathSeparator}$name.png');
  bool get _isFresh => _sel == _fresh;
  bool get _paddleReady => PaddleOcr.installed(_ocrDir);

  @override
  void initState() {
    super.initState();
    app.picturesChanged.addListener(_onPicturesChanged);
    _reload();
    _select(widget.capture != null
        ? _fresh
        : (_names.isEmpty ? null : _names.first));
  }

  @override
  void dispose() {
    app.picturesChanged.removeListener(_onPicturesChanged);
    _nameFocus.dispose();
    _name.dispose();
    _want.dispose();
    super.dispose();
  }

  /// Renamed / replaced / deleted (also from the controller): show the
  /// list and the selected picture anew.
  void _onPicturesChanged() {
    if (!mounted) return;
    _reload();
    final keep = _sel == _fresh || _names.contains(_sel);
    _select(keep ? _sel : (widget.capture != null ? _fresh : (_names.isEmpty ? null : _names.first)));
  }

  void _reload() {
    final dir = Directory(_dir)..createSync(recursive: true);
    _names = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .map((f) {
      final n = f.path.replaceAll('\\', '/').split('/').last;
      return n.substring(0, n.length - 4);
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  String _freeName() {
    var n = 1;
    while (_names.any((x) => x.toLowerCase() == 'картинка $n')) {
      n++;
    }
    return 'картинка $n';
  }

  void _select(String? sel) {
    _sel = sel;
    _nameError = null;
    _text = '';
    _ocrNote = '';
    _want.text = '';
    _bitmap = null;
    _png = null;
    try {
      if (sel == _fresh) {
        _bitmap = widget.capture!.image;
        _png = pngEncode(_bitmap!);
        _name.text = _freeName();
      } else if (sel != null) {
        _png = _file(sel).readAsBytesSync();
        _bitmap = pngDecode(_png!);
        _name.text = sel;
      }
    } catch (e) {
      _ocrNote = 'Не удалось открыть картинку: $e';
    }
    if (mounted) setState(() {});
    _recognize();
  }

  Future<void> _recognize() async {
    final img = _bitmap;
    if (img == null) return;
    final engine = app.settings.ocrEngine;
    if (engine == 'paddle' && !_paddleReady) {
      setState(() {
        _text = '';
        _ocrNote = 'Точное распознавание ещё не установлено.';
      });
      return;
    }
    final job = ++_job;
    setState(() {
      _busy = true;
      _ocrNote = '';
    });
    final sw = Stopwatch()..start();
    String text, note;
    try {
      if (engine == 'paddle') {
        text = await _paddleInIsolate(_ocrDir, img.w, img.h, img.bgra);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        text = ocrBitmap(app.backend, img);
      }
      note = text.isEmpty
          ? 'Текст не найден (${sw.elapsedMilliseconds} мс).'
          : 'Прочитано за ${sw.elapsedMilliseconds} мс.';
    } catch (e) {
      text = '';
      note = '$e';
    }
    if (!mounted || job != _job) return;
    setState(() {
      _busy = false;
      _text = text;
      _ocrNote = note;
      if (_want.text.isEmpty && text.isNotEmpty) {
        _want.text = text.split('\n').first.trim();
      }
    });
  }

  void _setEngine(String e) {
    app.settings.ocrEngine = e;
    app.settings.ocrChosen = true;
    app.saveSettings();
    setState(() {});
    _recognize();
  }

  Future<void> _installPaddle() async {
    setState(() {
      _install = 0;
      _installNote = '';
    });
    try {
      await installPaddle(_ocrDir, (done, file) {
        if (mounted) setState(() => _install = done);
      });
      _installNote = 'Установлено. Интернет больше не нужен.';
    } catch (e) {
      _installNote = 'Не получилось: $e';
    }
    if (!mounted) return;
    setState(() => _install = null);
    _recognize();
  }

  void _importPaddle() {
    final path = app.backend.pickFile(
        save: false, title: 'Файл PaddleOCR для SmartClicker (.zip)', ext: 'zip');
    if (path == null) return;
    try {
      final lost = importPaddleZip(_ocrDir, path);
      _installNote = lost.isEmpty
          ? 'Установлено из файла.'
          : 'В архиве не хватает: ${lost.join(', ')}';
    } catch (e) {
      _installNote = 'Не получилось прочитать файл: $e';
    }
    setState(() {});
    _recognize();
  }

  String? _checkName(String raw, {String? except}) {
    final err = ScriptStore.validateName(raw, allowPath: false);
    if (err != null) return err;
    final n = raw.trim().toLowerCase();
    if (_names.any((x) => x.toLowerCase() == n && x != except)) {
      return 'Такое имя уже занято';
    }
    return null;
  }

  Future<void> _saveOrRename() async {
    final fresh = _isFresh;
    final old = fresh ? null : _sel;
    final name = _name.text.trim();
    if (!fresh && name == old) return;
    final err = _checkName(_name.text, except: old);
    if (err != null) {
      setState(() => _nameError = err);
      return;
    }
    if (!fresh) {
      // Scripts that use the picture are fixed only after confirmation.
      final text = _text, note = _ocrNote, want = _want.text;
      if (!await renamePictureWithScripts(context, app, old!, name) || !mounted) return;
      _reload();
      _sel = name;
      setState(() {
        _text = text;
        _ocrNote = note;
        _want.text = want;
      });
      return;
    }
    try {
      _file(name).writeAsBytesSync(_png!);
    } catch (e) {
      setState(() => _nameError = '$e');
      return;
    }
    _reload();
    final text = _text, note = _ocrNote, want = _want.text;
    _sel = name;
    _nameError = null;
    setState(() {
      _text = text;
      _ocrNote = note;
      _want.text = want;
    });
    _copy('click_image("$name")',
        fresh ? 'Картинка сохранена' : 'Картинка переименована');
  }

  /// Deleting warns which scripts use the picture; the list is refreshed by
  /// [_onPicturesChanged].
  Future<void> _delete(String name) => deletePictureAsk(context, app, name);

  /// Right click on a saved picture.
  Future<void> _menu(String n, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'uses', child: Text('Где используется')),
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'replace', child: Text('Заменить снимком')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'uses':
        showPictureUses(context, app, n);
      case 'rename':
        _select(n);
        _nameFocus.requestFocus();
        _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
      case 'replace':
        app.replacePicture(n);
      case 'delete':
        _delete(n);
    }
  }

  void _copy(String code, [String title = 'Скопировано']) {
    Clipboard.setData(ClipboardData(text: code));
    app.notify(title, 'В буфере обмена: $code', level: 'ok');
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text('Картинки и текст на экране',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.crop_free, size: 18),
                label: const Text('Выделить область'),
                onPressed: () => app.startPick('region'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 230, child: _list()),
              const VerticalDivider(width: 1),
              Expanded(child: _sel == null ? _empty() : _details()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Здесь появляется то, что вы выделили на экране.\n\n'
            'Нажмите «Выделить область», наведите курсор на левый верхний '
            'угол нужного места и нажмите Ctrl, затем на правый нижний — и снова Ctrl.\n\n'
            'Окно покажет вырезанный кусок экрана, прочитанный в нём текст '
            'и готовые команды для скрипта.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.45),
          ),
        ),
      );

  Widget _list() => ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          if (widget.capture != null)
            ListTile(
              dense: true,
              selected: _isFresh,
              leading: const Icon(Icons.crop_free, size: 18),
              title: const Text('Только что выделено'),
              subtitle: Text('${widget.capture!.w} × ${widget.capture!.h} px',
                  style: const TextStyle(fontSize: 11.5)),
              onTap: () => _select(_fresh),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('СОХРАНЁННЫЕ КАРТИНКИ (${_names.length})',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: _muted,
                          fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 18),
                  tooltip: 'Открыть папку с картинками',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => app.openFolder(_dir),
                ),
              ],
            ),
          ),
          if (_names.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 12, 0),
              child: Text(
                  'Пока пусто. Выделите кнопку или значок и нажмите «Сохранить» — '
                  'скрипт сможет находить их командой click_image.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.35)),
            ),
          for (final n in _names)
            GestureDetector(
              onSecondaryTapDown: (d) => _menu(n, d.globalPosition),
              child: ListTile(
                dense: true,
                selected: _sel == n,
                leading: const Icon(Icons.image_outlined, size: 18),
                title: Text(n, overflow: TextOverflow.ellipsis),
                onTap: () => _select(n),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Удалить',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(n),
                ),
              ),
            ),
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600)),
      );

  Widget _cmd(String code, String hint) => Tooltip(
        message: hint,
        child: ActionChip(
          label: Text(code,
              style: codeStyle.copyWith(fontSize: 12.5),
              overflow: TextOverflow.ellipsis),
          avatar: const Icon(Icons.copy, size: 15),
          onPressed: () => _copy(code),
        ),
      );

  Widget _details() {
    final cap = widget.capture;
    final fresh = _isFresh;
    final img = _bitmap;
    final engine = app.settings.ocrEngine;
    final area = fresh ? app.formatRegion(cap!.x, cap.y, cap.w, cap.h) : '';
    final want = _want.text.trim().replaceAll('"', "'");
    final name = _name.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF14161B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.all(8),
            child: _png == null
                ? const Center(child: Text('—', style: TextStyle(color: _muted)))
                : Image.memory(_png!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium),
          ),
          const SizedBox(height: 6),
          Text(
            img == null
                ? ''
                : fresh
                    ? 'Область экрана: x ${cap!.x}, y ${cap.y}, ширина ${cap.w}, высота ${cap.h} px'
                    : 'Сохранённая картинка, ${img.w} × ${img.h} px',
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
          _label(fresh ? 'СОХРАНИТЬ КАК ОБРАЗЕЦ ДЛЯ ПОИСКА' : 'ИМЯ КАРТИНКИ'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _nameError,
                    hintText: 'например: кнопка старт',
                  ),
                  onChanged: (_) => setState(() => _nameError = null),
                  onSubmitted: (_) => _saveOrRename(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed:
                    (!fresh && name == _sel) || name.isEmpty ? null : _saveOrRename,
                child: Text(fresh ? 'Сохранить' : 'Переименовать'),
              ),
            ],
          ),
          if (!fresh && _sel != null) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                icon: const Icon(Icons.manage_search, size: 18),
                label: Text('Где используется (${app.pictureUses(_sel!).length})'),
                onPressed: () => showPictureUses(context, app, _sel!),
              ),
              Tooltip(
                message: 'Выделить на экране новую область (двумя нажатиями Ctrl) и сохранить её '
                    'под этим же именем. Скрипты менять не нужно — удобно, когда в игре изменилась кнопка',
                child: TextButton.icon(
                  icon: const Icon(Icons.crop_free, size: 18),
                  label: const Text('Заменить снимком'),
                  onPressed: app.busy ? null : () => app.replacePicture(_sel!),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _cmd('click_image("$_sel")', 'Кликнуть по картинке, если она есть на экране'),
              _cmd('click_image("$_sel", timeout: 10s)', 'Подождать картинку до 10 секунд и кликнуть'),
              _cmd('wait_image("$_sel", timeout: 10s)', 'Ждать появления картинки'),
              _cmd('find_image("$_sel")', 'Где картинка: {x, y} или null'),
              _cmd('click_image("$_sel", scale: "auto")', 'Найти, даже если картинка стала крупнее или мельче (окно другого размера)'),
            ]),
          ],
          _label('РАСПОЗНАВАНИЕ ТЕКСТА'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in ocrEngineLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: engine == e.key,
                  onSelected: (_) => _setEngine(e.key),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Распознать ещё раз',
                onPressed: _busy ? null : _recognize,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Выбранный способ используют и скрипты. Быстрое — доли секунды, '
              'хорошо читает обычный текст. Точное — медленнее (около секунды), '
              'но справляется с мелким, цветным и игровым текстом. '
              'Оба работают без интернета.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
          ),
          if (engine == 'paddle' && !_paddleReady) _installBox(),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 54, maxHeight: 130),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1D23),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(10),
            child: _busy
                ? const Row(children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Читаю…', style: TextStyle(color: _muted)),
                  ])
                : SingleChildScrollView(
                    child: SelectableText(
                      _text.isEmpty ? '(пусто)' : _text,
                      style: codeStyle.copyWith(
                          fontSize: 13.5, color: _text.isEmpty ? _muted : null),
                    ),
                  ),
          ),
          if (_ocrNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_ocrNote,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ),
          if (fresh) ...[
            _label('ГОТОВЫЕ КОМАНДЫ — НАЖМИТЕ, ЧТОБЫ СКОПИРОВАТЬ'),
            SizedBox(
              width: 420,
              child: TextField(
                controller: _want,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Какой текст искать в этой области',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (want.isNotEmpty) ...[
                _cmd('text_in($area, "$want")',
                    'true, если этот текст сейчас есть в области'),
                _cmd('wait_text($area, "$want", timeout: 30s)',
                    'Ждать, пока текст появится (до 30 секунд)'),
              ],
              _cmd('read_text($area)', 'Весь текст области'),
              _cmd('read_number($area)', 'Число из области: счётчик, цена'),
              _cmd(area, 'Только координаты: x, y, ширина, высота'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _installBox() => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2B3A55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Точное распознавание (PaddleOCR) нужно один раз скачать: '
              'около ${paddleDownloadMb(_ocrDir)} МБ с huggingface.co (модели) и '
              'nuget.org (библиотека ONNX Runtime от Microsoft). Больше программа '
              'в интернет не выходит; после установки всё работает без сети.',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 8),
            if (_install != null) ...[
              LinearProgressIndicator(value: _install),
              const SizedBox(height: 4),
              Text('Скачиваю… ${(_install! * 100).round()}%',
                  style: const TextStyle(fontSize: 12)),
            ] else
              Wrap(spacing: 8, runSpacing: 6, children: [
                FilledButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Скачать и установить'),
                  onPressed: _installPaddle,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
                  label: const Text('Из файла .zip (без интернета)'),
                  onPressed: _importPaddle,
                ),
              ]),
            if (_installNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_installNote, style: const TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      );
}
