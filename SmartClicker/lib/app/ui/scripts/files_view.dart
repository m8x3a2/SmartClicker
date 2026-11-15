// The "Файлы" tab under the editor: files the open script reads or writes
// (read_json, write_file…), their contents updated when another program
// (a neural network) changes them, and editing them right here.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;

class FilesView extends StatefulWidget {
  final AppController app;
  const FilesView({super.key, required this.app});

  @override
  State<FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<FilesView> {
  static const _maxShown = 200 * 1024; // bigger files are shown cut

  Timer? _timer;
  List<LinkedFile> _files = const [];
  String? _selected; // path
  String _stamp = '';
  String? _text; // null — no such file
  bool _editing = false;
  final _edit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _edit.dispose();
    super.dispose();
  }

  static String _stampOf(String path) {
    try {
      final s = File(path).statSync();
      if (s.type == FileSystemEntityType.notFound) return '';
      return '${s.modified.microsecondsSinceEpoch}:${s.size}';
    } catch (_) {
      return '';
    }
  }

  /// Once a second: the list of files (the script may have been edited) and
  /// the contents of the chosen one, if it changed on disk.
  void _tick() {
    if (!mounted) return;
    final files = widget.app.linkedFiles();
    var selected = _selected;
    if (selected == null || !files.any((f) => f.path == selected)) {
      selected = files.isEmpty ? null : files.first.path;
    }
    final stamp = selected == null ? '' : _stampOf(selected);
    final reload = selected != _selected || stamp != _stamp;
    setState(() {
      _files = files;
      if (selected != _selected) _editing = false;
      _selected = selected;
      if (reload && !_editing) {
        _stamp = stamp;
        _text = selected == null ? null : _read(selected);
      }
    });
  }

  static String? _read(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      var bytes = f.readAsBytesSync();
      final cut = bytes.length > _maxShown;
      if (cut) bytes = bytes.sublist(0, _maxShown);
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      return cut ? '$text\n… (показаны первые ${_maxShown ~/ 1024} КБ)' : text;
    } catch (e) {
      return 'Не удалось прочитать: $e';
    }
  }

  /// JSON is shown with indents, other text as it is.
  static String _pretty(String path, String text) {
    if (!path.toLowerCase().endsWith('.json')) return text;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  String _info(String path) {
    try {
      final s = File(path).statSync();
      if (s.type == FileSystemEntityType.notFound) return 'файла нет';
      final t = s.modified;
      String two(int n) => n.toString().padLeft(2, '0');
      final size = s.size < 1024 ? '${s.size} Б' : '${(s.size / 1024).toStringAsFixed(1)} КБ';
      return '$size · изменён ${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    } catch (_) {
      return '';
    }
  }

  void _save() {
    final path = _selected;
    if (path == null) return;
    final err = widget.app.saveLinkedFile(path, _edit.text);
    if (err != null) {
      widget.app.notify('Не сохранено', err, level: 'error');
      return;
    }
    setState(() => _editing = false);
    _stamp = '';
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF8B92A1);
    if (_files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Text(
          'Этот скрипт не работает с файлами. Здесь появятся файлы из read_json, write_json, wait_file, '
          'read_file, write_file и других команд — с содержимым, которое обновляется само, когда файл '
          'меняет другая программа (например, нейросеть). Справка → «Идеи использования».',
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
      );
    }
    final sel = _files.firstWhere((f) => f.path == _selected, orElse: () => _files.first);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 230,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
            children: [
              for (final f in _files)
                ListTile(
                  dense: true,
                  selected: f.path == sel.path,
                  selectedTileColor: const Color(0xFF2A2F3A),
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(f.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeStyle.copyWith(fontSize: 12.5)),
                  subtitle: Text(
                    '${f.uses}${f.line > 0 ? ' · строка ${f.line}' : ''}\n${_info(f.path)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  onTap: () {
                    if (f.line > 0) widget.app.revealLine.value = f.line;
                    setState(() {
                      _selected = f.path;
                      _editing = false;
                      _stamp = '';
                    });
                    _tick();
                  },
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _content(sel, muted)),
      ],
    );
  }

  Widget _content(LinkedFile f, Color muted) {
    final text = _text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(f.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: muted)),
              ),
              if (_editing) ...[
                TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Отмена')),
                FilledButton.tonal(onPressed: _save, child: const Text('Сохранить')),
              ] else ...[
                TextButton(
                  onPressed: () => setState(() {
                    _edit.text = text == null ? (f.path.toLowerCase().endsWith('.json') ? '{\n  \n}' : '') : _pretty(f.path, text);
                    _editing = true;
                  }),
                  child: Text(text == null ? 'Создать' : 'Изменить'),
                ),
                IconButton(
                  tooltip: 'Показать в папке',
                  icon: const Icon(Icons.folder_open, size: 18),
                  onPressed: text == null
                      ? () => widget.app.openFolder(File(f.path).parent.path)
                      : () => widget.app.showInFolder(f.path),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _editing
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _edit,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: codeStyle.copyWith(fontSize: 12.5),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  child: SelectableText(
                    text == null
                        ? 'Файла пока нет — его создаст скрипт или другая программа. Можно создать сразу: «Создать».'
                        : _pretty(f.path, text),
                    style: text == null
                        ? TextStyle(color: muted, fontSize: 12.5)
                        : codeStyle.copyWith(fontSize: 12.5, height: 1.4),
                  ),
                ),
        ),
      ],
    );
  }
}
