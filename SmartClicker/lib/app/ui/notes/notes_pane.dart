// The "My notes" tab of the help: .md notes that also go into the AI prompt.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../../core/storage/storage.dart';
import '../editor/code_editor.dart';
import '../widgets/name_dialog.dart';

/// All notes as one text (appended to the prompt for a neural network).
String notesAsText(AppPaths paths) {
  final dir = Directory(paths.notes);
  if (!dir.existsSync()) return '';
  final files = dir.listSync().whereType<File>().where(_isNote).toList()
    ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  final out = StringBuffer();
  for (final f in files) {
    final body = f.readAsStringSync().trim();
    if (body.isNotEmpty) out.write('\n### ${_title(f)}\n$body\n');
  }
  return out.toString();
}

bool _isNote(File f) => f.path.toLowerCase().endsWith('.md');
String _title(File f) {
  final name = f.path.replaceAll('\\', '/').split('/').last;
  return name.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
}

/// "My notes" tab of the help: the user's own descriptions of scripts and
/// modules, kept as .md files; can be imported and exported.
class NotesPane extends StatefulWidget {
  final AppController app;
  const NotesPane({super.key, required this.app});

  @override
  State<NotesPane> createState() => _NotesPaneState();
}

class _NotesPaneState extends State<NotesPane> {
  final _text = CodeController();
  final _noLine = ValueNotifier<int>(0);
  List<String> _names = [];
  String? _current;
  Timer? _saveTimer;
  bool _loading = false;
  int _epoch = 0;

  AppController get app => widget.app;
  String get _dir => app.paths.notes;
  File _file(String name) => File('$_dir${Platform.pathSeparator}$name.md');

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _reload();
    if (_names.isNotEmpty) _open(_names.first);
  }

  @override
  void dispose() {
    _flush();
    _text.dispose();
    _noLine.dispose();
    super.dispose();
  }

  void _reload() {
    final dir = Directory(_dir)..createSync(recursive: true);
    _names = dir.listSync().whereType<File>().where(_isNote).map(_title).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _changed() {
    if (_loading || _current == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final name = _current;
    if (name == null) return;
    try {
      _file(name).writeAsStringSync(_text.text);
    } catch (_) {}
  }

  void _open(String? name) {
    _flush();
    _loading = true;
    _current = name;
    _text.text = name == null ? '' : _file(name).readAsStringSync();
    _loading = false;
    _epoch++; // new editor = clean undo history
    if (mounted) setState(() {});
  }

  String? _validate(String raw, {String? except}) {
    final err = ScriptStore.validateName(raw, allowPath: false);
    if (err != null) return err;
    final name = raw.trim().toLowerCase();
    if (_names.any((n) => n.toLowerCase() == name && n != except)) {
      return 'Такая заметка уже есть';
    }
    return null;
  }

  String _freeName(String base) {
    var name = base, n = 2;
    while (_validate(name) != null && n < 1000) {
      name = '$base $n';
      n++;
    }
    return name;
  }

  Future<void> _create() async {
    final name = await askName(context, 'Новая заметка',
        initial: _freeName('Заметка'), validate: _validate);
    if (name == null) return;
    final n = name.trim();
    _file(n).writeAsStringSync('# $n\n\n');
    _reload();
    _open(n);
  }

  Future<void> _rename(String old) async {
    final name = await askName(context, 'Переименовать заметку',
        initial: old, validate: (s) => _validate(s, except: old));
    if (name == null || name.trim() == old) return;
    _flush();
    _file(old).renameSync(_file(name.trim()).path);
    _reload();
    _open(name.trim());
  }

  Future<void> _delete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить заметку «$name»?'),
        content: const Text('Вернуть её будет нельзя.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    if (_current == name) {
      _saveTimer?.cancel();
      _current = null;
    }
    _file(name).deleteSync();
    _reload();
    _open(_current ?? (_names.isEmpty ? null : _names.first));
  }

  void _import() {
    final path = app.backend
        .pickFile(save: false, title: 'Импорт заметки (.md)', ext: 'md');
    if (path == null) return;
    try {
      final src = File(path);
      final base = _title(src);
      final safe = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ').trim();
      final name = _freeName(safe.isEmpty ? 'Заметка' : safe);
      _file(name).writeAsStringSync(src.readAsStringSync());
      _reload();
      _open(name);
      app.notify('Заметка добавлена', name, level: 'ok');
    } catch (e) {
      app.notify('Не удалось прочитать файл', '$e', level: 'error');
    }
  }

  void _export(String name) {
    _flush();
    final path = app.backend.pickFile(
        save: true, title: 'Экспорт заметки', defaultName: '$name.md', ext: 'md');
    if (path == null) return;
    try {
      _file(name).copySync(path);
      app.notify('Заметка сохранена', path, level: 'ok');
    } catch (e) {
      app.notify('Не удалось сохранить файл', '$e', level: 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF8B92A1);
    final cur = _current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _create,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новая'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('Импорт .md'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _names.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Здесь можно вести свои записи: описания своих скриптов '
                          'и функций («модулей»), координаты, памятки.\n\n'
                          'Заметки — обычные файлы .md, их можно импортировать и '
                          'выгружать. Они добавляются в «Промпт для ИИ», так что '
                          'нейросеть узнает о ваших функциях.',
                          style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final n in _names)
                            ListTile(
                              dense: true,
                              selected: n == cur,
                              leading: const Icon(Icons.description_outlined, size: 18),
                              title: Text(n, overflow: TextOverflow.ellipsis),
                              onTap: () => _open(n),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Действия',
                                icon: const Icon(Icons.more_vert, size: 18),
                                onSelected: (a) => switch (a) {
                                  'rename' => _rename(n),
                                  'export' => _export(n),
                                  _ => _delete(n),
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'rename', child: Text('Переименовать')),
                                  PopupMenuItem(
                                      value: 'export', child: Text('Экспорт в .md')),
                                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton.icon(
                  onPressed: () => app.openFolder(_dir),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Папка заметок'),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: cur == null
              ? const Center(
                  child: Text('Создайте заметку или импортируйте файл .md',
                      style: TextStyle(color: muted)))
              : CodeEditor(
                  key: ValueKey('note$_epoch'),
                  controller: _text,
                  currentLine: _noLine,
                  errorLine: _noLine,
                  suggestions: false,
                  hoverHints: app.settings.hintHover,
                ),
        ),
      ],
    );
  }
}
