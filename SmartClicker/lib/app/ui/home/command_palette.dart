// Command palette (Ctrl+K): a search over the actions, pages and settings of
// the program and the scripts — type a few letters, Enter does it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';
import '../new_script/new_script_dialog.dart';
import '../scripts/profile_dialog.dart';
import '../scripts/search_dialog.dart';
import '../scripts/share_dialogs.dart' show importFromZip;
import '../scripts/trash_dialog.dart';
import '../settings/quick_settings.dart';
import '../widgets/page_parts.dart';

class PaletteCommand {
  final String title;

  /// Other words it is found by ("тест" for «Тест без кликов»…).
  final String keywords;
  final IconData icon;
  final VoidCallback action;
  const PaletteCommand(this.title, this.icon, this.action, {this.keywords = ''});
}

/// How well [query] fits a command: every word of the query must be in the
/// title or keywords; a title starting with the query is the best. 0 — no.
int paletteScore(String title, String keywords, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 1;
  final t = title.toLowerCase(), all = '$t ${keywords.toLowerCase()}';
  final words = q.split(RegExp(r'\s+'));
  if (!words.every(all.contains)) return 0;
  if (t.startsWith(q)) return 4;
  if (t.contains(q)) return 3;
  return words.every(t.contains) ? 2 : 1;
}

/// The commands; [goPage] switches the page on the left.
List<PaletteCommand> paletteCommands(BuildContext context, AppController app, void Function(int) goPage) {
  final s = app.settings;
  void toggle(void Function() change, String what, bool on) {
    change();
    app.saveSettings();
    app.notify('Настройки', '$what: ${on ? 'включено' : 'выключено'}', level: 'ok');
  }

  return [
    // Pages
    PaletteCommand('Скрипты', Icons.code, () => goPage(0), keywords: 'страница редактор список'),
    PaletteCommand('Инструменты', Icons.my_location, () => goPage(1), keywords: 'страница координаты цвет'),
    PaletteCommand('Автозапуск', Icons.schedule, () => goPage(2), keywords: 'страница расписание по программе по файлу'),
    PaletteCommand('История запусков', Icons.history, () => goPage(3), keywords: 'страница фильтры ошибки'),
    PaletteCommand('Справка', Icons.menu_book, () => goPage(4), keywords: 'страница помощь руководство язык'),
    PaletteCommand('Картинки', Icons.image_search, () => goPage(5), keywords: 'страница распознавание текст ocr'),
    PaletteCommand('Буфер обмена', Icons.content_paste, () => goPage(6), keywords: 'страница история копирования'),
    PaletteCommand('Настройки', Icons.settings, () => goPage(7), keywords: 'страница параметры'),
    // Run
    PaletteCommand('Запустить открытый скрипт', Icons.play_arrow, () {
      goPage(0);
      app.run();
    }, keywords: 'запуск старт пуск'),
    PaletteCommand('Запустить пошагово', Icons.skip_next, () {
      goPage(0);
      app.run(step: true);
    }, keywords: 'отладка шаг'),
    PaletteCommand('Запустить замедленно', Icons.slow_motion_video, () {
      goPage(0);
      app.run(slow: true);
    }, keywords: 'отладка медленно'),
    PaletteCommand('Остановить скрипт или запись', Icons.stop, app.stop, keywords: 'стоп'),
    PaletteCommand('Пауза / продолжить', Icons.pause, app.togglePause),
    PaletteCommand('Запись действий', Icons.fiber_manual_record, app.toggleRecording, keywords: 'записать'),
    PaletteCommand(s.dryRun ? 'Тест без кликов: выключить' : 'Тест без кликов: включить', Icons.science_outlined,
        () => toggle(() => s.dryRun = !s.dryRun, 'Тест без кликов', !s.dryRun),
        keywords: 'тестовый режим проверка сухой'),
    PaletteCommand('Проверить скрипт на ошибки', Icons.rule, app.checkNow, keywords: 'проверка'),
    PaletteCommand('Профиль последнего запуска', Icons.speed, () => showProfile(context, app),
        keywords: 'медленно тормозит время профилировщик'),
    // Scripts
    PaletteCommand('Новый скрипт…', Icons.note_add_outlined, () => showNewScript(context, app),
        keywords: 'создать шаблон'),
    PaletteCommand('Сохранить', Icons.save_outlined, app.save, keywords: 'ctrl+s'),
    PaletteCommand('Сохранить все скрипты', Icons.save, app.saveAll),
    PaletteCommand('Поиск по всем скриптам…', Icons.manage_search, () => showScriptSearch(context, app),
        keywords: 'найти ctrl+shift+f'),
    PaletteCommand('Корзина…', Icons.restore_from_trash_outlined, () => showTrash(context, app),
        keywords: 'удалённые вернуть восстановить'),
    PaletteCommand('Экспорт всех скриптов в ZIP…', Icons.archive_outlined, app.exportScripts),
    PaletteCommand('Импорт из ZIP…', Icons.unarchive_outlined, () => importFromZip(context, app)),
    PaletteCommand('Восстановить примеры', Icons.auto_awesome_outlined, app.restoreExamples),
    PaletteCommand('Добавить скрипты-проверки настроек', Icons.fact_check_outlined, app.addCheckScripts),
    // Tools
    PaletteCommand('Взять координаты кликом', Icons.ads_click, () => app.startPick('point'),
        keywords: 'точка координаты f6'),
    PaletteCommand('Выделить область (два Ctrl)', Icons.crop, () => app.startPick('region'),
        keywords: 'область картинка вырезать'),
    PaletteCommand('Убрать все точки-ориентиры', Icons.location_off_outlined, app.clearLandmarks,
        keywords: 'f4 метки'),
    PaletteCommand('Мини-панель поверх всех окон', Icons.picture_in_picture_alt, () => app.setCompact(true),
        keywords: 'компактно'),
    PaletteCommand('Свернуть в трей', Icons.minimize, app.hideToTray, keywords: 'спрятать'),
    PaletteCommand('Быстрые настройки…', Icons.tune, () => showQuickSettings(context, app)),
    // Data and settings
    PaletteCommand('Резервная копия всего…', Icons.backup_outlined, app.saveBackup, keywords: 'бэкап сохранить'),
    PaletteCommand('Открыть папку с данными', Icons.folder_open, () => app.openFolder(app.paths.base),
        keywords: 'appdata файлы'),
    PaletteCommand('Открыть папку files (картинки, JSON)', Icons.folder_outlined,
        () => app.openFolder(app.paths.files)),
    PaletteCommand(s.showClicks ? 'Показывать место клика: выключить' : 'Показывать место клика: включить',
        Icons.radio_button_checked, () => toggle(() => s.showClicks = !s.showClicks, 'Место клика', !s.showClicks),
        keywords: 'маркер кольцо'),
    PaletteCommand(
        s.clipHistory ? 'История буфера обмена: выключить' : 'История буфера обмена: включить',
        Icons.content_paste_go,
        () => app.setClipHistory(!s.clipHistory),
        keywords: 'буфер копирование'),
    if (app.safeMode || app.automationOff || app.automationWaitSec > 0)
      PaletteCommand('Включить автоматику (выйти из безопасного режима)', Icons.shield_outlined,
          app.enableAutomationNow,
          keywords: 'безопасный режим расписание'),
    // Scripts by name
    for (final name in app.scripts)
      PaletteCommand('Открыть скрипт: $name', Icons.description_outlined, () {
        app.open(name);
        goPage(0);
      }),
  ];
}

Future<void> showCommandPalette(BuildContext context, AppController app, void Function(int) goPage) =>
    showDialog<void>(
      context: context,
      builder: (c) => _Palette(paletteCommands(context, app, goPage)),
    );

class _Palette extends StatefulWidget {
  final List<PaletteCommand> commands;
  const _Palette(this.commands);

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _query = TextEditingController();
  int _sel = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<PaletteCommand> _found() {
    final scored = [
      for (final c in widget.commands)
        if (paletteScore(c.title, c.keywords, _query.text) case final s when s > 0) (c, s)
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (c, _) in scored.take(60)) c];
  }

  void _do(PaletteCommand c) {
    Navigator.pop(context);
    c.action();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found();
    if (_sel >= found.length) _sel = found.isEmpty ? 0 : found.length - 1;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: 560,
        height: 420,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                setState(() => _sel = (_sel + 1).clamp(0, found.length - 1)),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                setState(() => _sel = (_sel - 1).clamp(0, found.length - 1)),
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (found.isNotEmpty) _do(found[_sel]);
            },
          },
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() => _sel = 0),
                decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.bolt, size: 18),
                    hintText: 'Что сделать? Например: тест, призрак, корзина, папка с данными…'),
              ),
            ),
            Expanded(
              child: found.isEmpty
                  ? const Center(child: Text('Ничего не нашлось', style: TextStyle(color: mutedText)))
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        selected: i == _sel,
                        selectedTileColor: const Color(0xFF2A2F3A),
                        leading: Icon(found[i].icon, size: 18),
                        title: Text(found[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _do(found[i]),
                      ),
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text('↑↓ — выбрать, Enter — сделать, Esc — закрыть',
                  style: TextStyle(color: mutedText, fontSize: 11.5)),
            ),
          ]),
        ),
      ),
    );
  }
}
