// Tree of scripts and folders on the left: open, drag to folders, context menus.

import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../../../core/storage/storage.dart';
import '../new_script/new_script_dialog.dart';
import '../widgets/name_dialog.dart';
import 'share_dialogs.dart';
import 'ask_dialog.dart';

class _Folder {
  final String path;
  final Map<String, _Folder> dirs = {};
  final List<String> scripts = [];
  _Folder(this.path);

  _Folder child(String name) => dirs.putIfAbsent(
      name, () => _Folder(path.isEmpty ? name : '$path/$name'));

  _Folder descend(String folderPath) {
    var node = this;
    if (folderPath.isEmpty) return node;
    for (final part in folderPath.split('/')) {
      node = node.child(part);
    }
    return node;
  }
}

class ScriptList extends StatelessWidget {
  final AppController app;
  const ScriptList(this.app, {super.key});

  String get _where =>
      app.selectedFolder.isEmpty ? '' : ' в «${app.selectedFolder}»';

  Future<void> _create(BuildContext context) =>
      showNewScript(context, app, where: _where);

  Future<void> _createFolder(BuildContext context) async {
    await askName(context, 'Новая папка$_where', validate: app.createFolder);
  }

  void _menu(BuildContext context, String action) {
    switch (action) {
      case 'root':
        app.selectFolder('');
      case 'examples':
        app.restoreExamples();
      case 'checks':
        app.addCheckScripts();
      case 'clear':
        _confirmDeleteAll(context);
      case 'export':
        app.exportScripts();
      case 'import':
        importFromZip(context, app);
      case 'open':
        app.openFolder(app.paths.scripts);
    }
  }

  Future<String?> _popup(
          BuildContext context, Offset at, List<PopupMenuEntry<String>> items) =>
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: items,
      );

  Future<bool> _confirm(BuildContext context, String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить')),
          ],
        ),
      ) ==
      true;

  /// "Delete all scripts": asks first, offers an export to ZIP before it.
  Future<void> _confirmDeleteAll(BuildContext context) async {
    if (app.busy || app.scripts.isEmpty) return;
    final t = Theme.of(context);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever, color: t.colorScheme.error),
        title: const Text('Удалить все скрипты?'),
        content: SizedBox(
          width: 420,
          child: Text(
              'Будут удалены все скрипты (${app.scripts.length}) и папки'
              '${app.unsaved.isEmpty ? '' : ', в том числе несохранённые изменения'}. '
              'Вернуть их будет нельзя.\n\n'
              'Картинки, настройки, история и заметки останутся.\n\n'
              'Совет: сначала сохраните всё в ZIP — потом можно будет вернуть '
              'через «Импорт из ZIP…».'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'export'),
              child: const Text('Сначала экспорт в ZIP…')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: t.colorScheme.error, foregroundColor: t.colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Удалить все'),
          ),
        ],
      ),
    );
    if (v == 'export') {
      app.exportScripts();
      if (context.mounted) await _confirmDeleteAll(context); // ask again after the export
    } else if (v == 'delete') {
      app.deleteAllScripts();
    }
  }

  /// Lets the user choose a destination folder; returns null if cancelled.
  Future<String?> _chooseFolder(BuildContext context) => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Переместить в папку'),
          children: [
            for (final f in ['', ...app.folders])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f),
                child: Row(
                  children: [
                    const Icon(Icons.folder, size: 18, color: Color(0xFFE0A66A)),
                    const SizedBox(width: 10),
                    Flexible(child: Text(f.isEmpty ? '(корень — без папки)' : f)),
                  ],
                ),
              ),
          ],
        ),
      );

  Future<void> _scriptMenu(BuildContext context, Offset at, String script) async {
    if (app.busy) return;
    final base = ScriptStore.baseOf(script);
    final v = await _popup(context, at, const [
      PopupMenuItem(value: 'open', child: Text('Открыть')),
      PopupMenuItem(value: 'rename', child: Text('Переименовать…')),
      PopupMenuItem(value: 'move', child: Text('Переместить в папку…')),
      PopupMenuItem(value: 'copy', child: Text('Создать копию')),
      PopupMenuItem(value: 'share', child: Text('Поделиться (ZIP с картинками)…')),
      PopupMenuItem(value: 'answers', child: Text('Ответы на вопросы (ask)…')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'delete', child: Text('Удалить…')),
    ]);
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'open':
        app.open(script);
      case 'rename':
        await askName(context, 'Переименовать «$base»',
            initial: script, validate: (n) => app.renameScript(script, n));
      case 'move':
        final folder = await _chooseFolder(context);
        if (folder == null) return;
        final err = app.moveScript(script, folder);
        if (err != null) app.notify('Не удалось переместить', err, level: 'warn');
      case 'copy':
        app.duplicate(script);
      case 'share':
        await shareScriptDialog(context, app, script);
      case 'answers':
        final (asks, initial) = app.answersOf(script);
        if (asks.isEmpty) {
          app.notify('Вопросов нет',
              '«$script» ничего не спрашивает: в нём нет ask("…", …) с готовым текстом');
          return;
        }
        final got = await showAskDialog(context, script, asks, initial, saveOnly: true);
        if (got != null) app.saveAnswers(script, got);
      case 'delete':
        if (await _confirm(context, 'Удалить скрипт?',
            '«$script» будет удалён без возможности восстановления.')) {
          app.deleteScript(script);
        }
    }
  }

  Future<void> _folderMenu(BuildContext context, Offset at, String path) async {
    if (app.busy) return;
    final v = await _popup(context, at, [
      const PopupMenuItem(value: 'script', child: Text('Новый скрипт здесь…')),
      const PopupMenuItem(value: 'folder', child: Text('Новая папка здесь…')),
      const PopupMenuItem(value: 'rename', child: Text('Переименовать…')),
      const PopupMenuDivider(),
      PopupMenuItem(
          value: 'dry',
          enabled: app.scriptsIn(path).isNotEmpty,
          child: Text(path == checksFolder
              ? 'Прогнать все проверки без кликов (сводка)'
              : 'Прогнать все скрипты папки без кликов (сводка)')),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'delete', child: Text('Удалить…')),
    ]);
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'script':
        app.selectFolder(path);
        await _create(context);
      case 'folder':
        app.selectFolder(path);
        await _createFolder(context);
      case 'dry':
        app.runFolderDry(path);
      case 'rename':
        await askName(context, 'Переименовать папку',
            initial: ScriptStore.baseOf(path),
            validate: (n) => app.renameFolder(path, n));
      case 'delete':
        final count = app.scriptsIn(path).length;
        if (await _confirm(
            context,
            'Удалить папку?',
            count == 0
                ? 'Папка «$path» пуста и будет удалена.'
                : 'Папка «$path» и все скрипты в ней ($count шт.) будут удалены без возможности восстановления.')) {
          app.deleteFolder(path);
        }
    }
  }

  /// Drag and drop: a script dropped on a folder (or on a script inside
  /// it) moves there.
  void _moveTo(String script, String folder) {
    if (ScriptStore.folderOf(script) == folder) return;
    final err = app.moveScript(script, folder);
    if (err != null) app.notify('Не удалось переместить', err, level: 'warn');
  }

  Widget _dropTarget(String folder, Widget Function(bool over) build) =>
      DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _moveTo(d.data, folder),
        builder: (_, candidates, _) => build(candidates.isNotEmpty &&
            ScriptStore.folderOf(candidates.first ?? '') != folder),
      );

  List<Widget> _rows(BuildContext context, _Folder node, int depth) {
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[];
    Widget row(
            {required IconData icon,
            required String label,
            required bool selected,
            required VoidCallback? onTap,
            required void Function(Offset at) onMenu,
            Widget? leading,
            bool dropHover = false,
            bool bold = false}) =>
        InkWell(
          onTap: onTap,
          onSecondaryTapUp: (d) => onMenu(d.globalPosition),
          child: Container(
            color: dropHover
                ? scheme.primary.withValues(alpha: 0.32)
                : selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : null,
            padding: EdgeInsets.fromLTRB(8.0 + depth * 14, 6, 8, 6),
            child: Row(
              children: [
                SizedBox(width: 18, child: leading),
                Icon(icon, size: 17, color: bold ? const Color(0xFFE0A66A) : null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                          color: selected && !bold ? scheme.primary : null)),
                ),
              ],
            ),
          ),
        );

    final dirNames = node.dirs.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in dirNames) {
      final dir = node.dirs[name]!;
      final open = !app.collapsed.contains(dir.path);
      out.add(_dropTarget(
        dir.path,
        (over) => row(
          icon: open ? Icons.folder_open : Icons.folder,
          label: name,
          bold: true,
          dropHover: over,
          selected: app.selectedFolder == dir.path &&
              ScriptStore.folderOf(app.current ?? '') != dir.path,
          leading:
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16),
          onTap: () => app.toggleFolder(dir.path),
          onMenu: (at) => _folderMenu(context, at, dir.path),
        ),
      ));
      if (open) out.addAll(_rows(context, dir, depth + 1));
    }
    for (final script in node.scripts) {
      final line = row(
        icon: Icons.description_outlined,
        label: ScriptStore.baseOf(script) +
            (app.settings.scriptKeys[script] == null
                ? ''
                : '  [${app.settings.scriptKeys[script]!.toUpperCase()}]') +
            (app.isUnsaved(script) ? '  ●' : ''),
        selected: script == app.current,
        onTap: app.busy ? null : () => app.open(script),
        onMenu: (at) => _scriptMenu(context, at, script),
      );
      out.add(_dropTarget(
        node.path,
        (_) => Draggable<String>(
          data: script,
          maxSimultaneousDrags: app.busy ? 0 : 1,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            color: const Color(0xFF2B3A55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(ScriptStore.baseOf(script),
                      style: const TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
          ),
          child: line,
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final root = _Folder('');
    for (final f in app.folders) {
      root.descend(f);
    }
    for (final sc in app.scripts) {
      root.descend(ScriptStore.folderOf(sc)).scripts.add(sc);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 2, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Скрипты',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Новый скрипт$_where',
                icon: const Icon(Icons.note_add_outlined, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: app.busy ? null : () => _create(context),
              ),
              IconButton(
                tooltip: 'Новая папка$_where',
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: app.busy ? null : () => _createFolder(context),
              ),
              PopupMenuButton<String>(
                tooltip: 'Ещё',
                icon: const Icon(Icons.more_vert, size: 20),
                enabled: !app.busy,
                onSelected: (v) => _menu(context, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'root', child: Text('Создавать в корне (снять выбор папки)')),
                  PopupMenuItem(
                      value: 'examples', child: Text('Восстановить примеры')),
                  PopupMenuItem(
                      value: 'checks',
                      child: Text('Добавить скрипты-проверки настроек')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'clear', child: Text('Удалить все скрипты…')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                      value: 'export', child: Text('Экспорт всех скриптов в ZIP…')),
                  PopupMenuItem(value: 'import', child: Text('Импорт из ZIP…')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'open', child: Text('Открыть папку на диске')),
                ],
              ),
            ],
          ),
        ),
        // Dropping a script on the empty space moves it out of its folder.
        Expanded(
          child: _dropTarget(
            '',
            (over) => Container(
              foregroundDecoration: over
                  ? BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2))
                  : null,
              child: ListView(children: _rows(context, root, 0)),
            ),
          ),
        ),
      ],
    );
  }
}
