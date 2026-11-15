// The «Буфер» page: history of the clipboard — search, pin, copy back, paste
// into the window the hotkey was pressed in, several at once or one by one.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/storage/clip_history.dart';
import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;
import '../widgets/hotkey_dialog.dart';
import '../widgets/page_parts.dart';

class ClipboardPage extends StatefulWidget {
  final AppController app;
  const ClipboardPage({super.key, required this.app});

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  final _search = TextEditingController();
  final Set<String> _picked = {}; // ids, in the order of picking
  final List<String> _order = [];

  AppController get app => widget.app;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ClipItem> _visible() {
    final q = _search.text.trim().toLowerCase();
    final all = app.clips.items;
    if (q.isEmpty) return all;
    return [
      for (final i in all)
        if (i.title.toLowerCase().contains(q) || (i.text ?? '').toLowerCase().contains(q)) i
    ];
  }

  List<ClipItem> _pickedItems() {
    final byId = {for (final i in app.clips.items) i.id: i};
    return [for (final id in _order) ?byId[id]];
  }

  void _toggle(ClipItem i) => setState(() {
        if (_picked.remove(i.id)) {
          _order.remove(i.id);
        } else {
          _picked.add(i.id);
          _order.add(i.id);
        }
      });

  String _size(int b) => b < 1024 ? '$b Б' : b < 1048576 ? '${(b / 1024).toStringAsFixed(1)} КБ' : '${(b / 1048576).toStringAsFixed(1)} МБ';

  Future<void> _limits() async {
    final items = TextEditingController(text: '${app.settings.clipMaxItems}');
    final mb = TextEditingController(text: '${app.settings.clipMaxMb}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Сколько хранить'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: items, decoration: const InputDecoration(labelText: 'Записей, не больше')),
            TextField(controller: mb, decoration: const InputDecoration(labelText: 'Мегабайт, не больше')),
            const SizedBox(height: 10),
            const Text('Старые записи удаляются сами (закреплённые — никогда). По умолчанию 30 записей и 10 МБ.',
                style: TextStyle(color: mutedText, fontSize: 12.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = int.tryParse(items.text.trim()) ?? app.settings.clipMaxItems;
    final m = int.tryParse(mb.text.trim()) ?? app.settings.clipMaxMb;
    if (n > 1000 || m > 200) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Много для истории'),
          content: const Text('Больше 1000 записей или 200 МБ: программа может начать тормозить или упасть, '
              'а папка данных — сильно вырасти. Желательно не больше 200 МБ и 1000 записей. Всё равно поставить?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Да, поставить')),
          ],
        ),
      );
      if (sure != true) return;
    }
    app.setClipLimits(items: n, mb: m);
  }

  /// What was pasted in the "one by one" mode: put back or throw away.
  Future<void> _trash() => showDialog<void>(
        context: context,
        builder: (c) => ListenableBuilder(
          listenable: app.clipVersion,
          builder: (c, _) {
            final trash = app.clips.trash;
            return AlertDialog(
              title: Text('Корзина буфера (${trash.length})'),
              content: SizedBox(
                width: 520,
                height: 380,
                child: trash.isEmpty
                    ? const Center(
                        child: Text('Пусто. Сюда попадает вставленное в режиме «по очереди»',
                            style: TextStyle(color: mutedText)))
                    : ListView(children: [
                        for (final i in trash)
                          ListTile(
                            dense: true,
                            title: Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(timeStamp(i.at), style: const TextStyle(color: mutedText)),
                            trailing: TextButton(
                              onPressed: () => app.restoreClip(i),
                              child: const Text('Вернуть'),
                            ),
                          ),
                      ]),
              ),
              actions: [
                TextButton(
                  onPressed: trash.isEmpty ? null : app.emptyClipTrash,
                  child: const Text('Очистить корзину'),
                ),
                FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть')),
              ],
            );
          },
        ),
      );

  Future<void> _assignKey() async {
    final combo = await captureHotkey(context, app);
    if (combo == null) return;
    if (app.hotkeyTaken(combo, app.settings.clipKey)) {
      app.notify('Клавиша занята', '${combo.toUpperCase()} уже назначена другому действию или скрипту',
          level: 'warn');
      return;
    }
    app.settings.clipKey = combo;
    app.saveSettings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.clipVersion]),
      builder: (context, _) {
        final on = app.settings.clipHistory;
        final items = _visible();
        final picked = _pickedItems();
        final target = app.clipTarget;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pageHeader('Буфер обмена', actions: [
              Text('Запоминать, что копирую', style: TextStyle(color: on ? null : mutedText)),
              const SizedBox(width: 8),
              Switch(value: on, onChanged: app.setClipHistory),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Клавиша показа:', style: const TextStyle(color: mutedText, fontSize: 12.5)),
                  OutlinedButton(onPressed: _assignKey, child: Text(app.settings.clipKey.toUpperCase())),
                  TextButton.icon(
                    onPressed: _limits,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text('Хранить: ${app.settings.clipMaxItems} шт., ${app.settings.clipMaxMb} МБ'
                        '  (занято ${app.clips.items.length} шт., ${_size(app.clips.totalBytes)})'),
                  ),
                  TextButton.icon(
                    onPressed: app.clips.items.isEmpty ? null : app.clearClips,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Очистить (кроме закреплённых)'),
                  ),
                  TextButton.icon(
                    onPressed: _trash,
                    icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
                    label: Text('Корзина (${app.clips.trash.length})'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 20, 4),
              child: Row(children: [
                Switch(value: app.settings.clipOneByOne, onChanged: on ? app.setClipOneByOne : null),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    app.settings.clipOneByOne
                        ? 'По очереди: ${app.settings.clipKey.toUpperCase()} в любом окне сразу вставляет следующую '
                            '(от старых к новым), вставленная уходит в корзину. Следующей: '
                            '${app.clips.nextInLine == null ? 'нечего — история пуста' : '«${app.clips.nextInLine!.title}»'}'
                        : 'По очереди — выключено: ${app.settings.clipKey.toUpperCase()} показывает этот список. '
                            'Включите, чтобы каждое нажатие сразу вставляло следующую запись, а вставленная уходила в корзину',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ]),
            ),
            if (!on)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Включите — и SmartClicker будет запоминать всё, что вы копируете: текст, файлы, картинки '
                  '(как Win+V, но больше и со списками файлов). Скопированное менеджерами паролей не запоминается. '
                  'Клавиша показа в любом окне открывает этот список; щелчок «Вставить» — и запись вставится туда, '
                  'где вы были. Можно отметить несколько: «все сразу» (текст подряд, файлы и картинки — одним '
                  'Ctrl+V) или «по очереди» — каждое нажатие клавиши показа вставляет следующую.',
                  style: TextStyle(color: mutedText, fontSize: 12.5),
                ),
              ),
            if (target != null)
              Container(
                color: const Color(0xFF24405F),
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
                child: Row(children: [
                  const Icon(Icons.input, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Вставка в «${target.title.isEmpty ? target.process : target.title}» — '
                          'нажмите «Вставить» у записи')),
                ]),
              ),
            if (app.clipQueue.isNotEmpty)
              Container(
                color: const Color(0xFF1F4A3A),
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                child: Row(children: [
                  Expanded(
                      child: Text('Очередь: осталось ${app.clipQueue.length} из ${app.clipQueueTotal} — '
                          'в нужном окне жмите ${app.settings.clipKey.toUpperCase()}')),
                  TextButton(onPressed: app.stopClipQueue, child: const Text('Остановить')),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Поиск'),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(on ? 'Пока пусто — скопируйте что-нибудь' : 'История выключена',
                          style: const TextStyle(color: mutedText)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: items.length,
                      itemBuilder: (_, n) => _tile(items[n], target != null),
                    ),
            ),
            // Below the list: appearing above it would move the rows under the mouse.
            if (picked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
                child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Отмечено: ${picked.length}', style: const TextStyle(color: mutedText)),
                  FilledButton.tonal(
                    onPressed: () => app.pasteClipsAtOnce(picked),
                    child: Text(target == null ? 'Все сразу в буфер' : 'Вставить все сразу'),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      app.startClipQueue(picked);
                      setState(() {
                        _picked.clear();
                        _order.clear();
                      });
                    },
                    child: const Text('Вставлять по очереди'),
                  ),
                  TextButton(
                    onPressed: () {
                      app.removeClips(picked);
                      setState(() {
                        _picked.clear();
                        _order.clear();
                      });
                    },
                    child: const Text('Удалить'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _picked.clear();
                      _order.clear();
                    }),
                    child: const Text('Снять отметки'),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(ClipItem i, bool hasTarget) {
    final picked = _picked.contains(i.id);
    final order = picked ? _order.indexOf(i.id) + 1 : 0;
    final leading = switch (i.kind) {
      'image' => SizedBox(
          width: 56,
          height: 40,
          child: Image.file(File(app.clips.imagePath(i)),
              fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported)),
        ),
      'files' => const SizedBox(width: 56, child: Icon(Icons.insert_drive_file_outlined)),
      _ => const SizedBox(width: 56, child: Icon(Icons.notes)),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: picked ? const Color(0xFF2A3550) : null,
      child: InkWell(
        onTap: () => _toggle(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(children: [
            SizedBox(
              width: 26,
              child: picked
                  ? CircleAvatar(radius: 11, child: Text('$order', style: const TextStyle(fontSize: 11)))
                  : const Icon(Icons.radio_button_unchecked, size: 18, color: mutedText),
            ),
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: i.kind == 'text' ? codeStyle.copyWith(fontSize: 12.5) : null),
                Text(
                    '${timeStamp(i.at)}${i.bytes > 0 ? ' · ${_size(i.bytes)}' : ''}'
                    '${i.kind == 'files' ? ' · ${i.files!.length} файл(ов)' : ''}',
                    style: const TextStyle(color: mutedText, fontSize: 11.5)),
              ]),
            ),
            IconButton(
              tooltip: i.pinned ? 'Открепить' : 'Закрепить — не удалится сам',
              icon: Icon(i.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
              onPressed: () => app.togglePinClip(i),
            ),
            IconButton(
              tooltip: 'Положить в буфер обмена',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                if (app.copyClip(i)) app.notify('Буфер обмена', 'Скопировано — вставьте Ctrl+V', level: 'ok');
              },
            ),
            if (hasTarget)
              FilledButton.tonal(onPressed: () => app.pasteClip(i), child: const Text('Вставить')),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => app.removeClips([i]),
            ),
          ]),
        ),
      ),
    );
  }
}
