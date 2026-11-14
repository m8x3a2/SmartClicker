// The "Autorun" page: tasks by schedule and rules "start when a program opens".

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/automation/autorun.dart';
import '../../state/app_controller.dart';
import '../../../core/storage/storage.dart';
import '../widgets/page_parts.dart';

class SchedulePage extends StatelessWidget {
  final AppController app;
  const SchedulePage({super.key, required this.app});

  /// New task, or changes [task] if given (the same window).
  Future<void> _editTask(BuildContext context, [ScheduleTask? task]) async {
    if (app.scripts.isEmpty) return;
    String two(int n) => n.toString().padLeft(2, '0');
    // A one-time task starts in 10 minutes unless told otherwise.
    final soon = DateTime.now().add(const Duration(minutes: 10));
    var script = task?.script ?? app.current ?? app.scripts.first;
    if (!app.scripts.contains(script)) script = app.scripts.first;
    var mode = task?.mode ?? 'daily';
    final time = TextEditingController(
        text: task?.time ?? (mode == 'once' ? '${soon.hour}:${two(soon.minute)}' : '12:00'));
    final date = TextEditingController(
        text: task != null && task.date.isNotEmpty
            ? task.dateLabel
            : '${two(soon.day)}.${two(soon.month)}.${soon.year}');
    final every = TextEditingController(text: '${task?.everyMin ?? 60}');
    String? error, dateError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(task == null ? 'Новая задача' : 'Изменить задачу'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Скрипт', style: TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: script,
                  items: [
                    for (final n in app.scripts)
                      DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => script = v ?? script),
                ),
                const SizedBox(height: 12),
                const Text('Когда запускать', style: TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: mode,
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('Один раз: в указанный день и время')),
                    DropdownMenuItem(value: 'daily', child: Text('Каждый день в указанное время')),
                    DropdownMenuItem(value: 'interval', child: Text('Каждые N минут')),
                  ],
                  onChanged: (v) => setState(() {
                    mode = v ?? mode;
                    error = dateError = null;
                  }),
                ),
                const SizedBox(height: 8),
                if (mode == 'once')
                  TextField(
                    controller: date,
                    decoration: InputDecoration(
                        labelText: 'Дата, например ${two(soon.day)}.${two(soon.month)}.${soon.year}',
                        errorText: dateError),
                  ),
                if (mode != 'interval')
                  TextField(
                    controller: time,
                    decoration: InputDecoration(
                        labelText: 'Время, например 14:30', errorText: error),
                  )
                else
                  TextField(
                    controller: every,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        labelText: 'Интервал в минутах', errorText: error),
                  ),
                if (mode == 'once')
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                        'После запуска задача выключится сама и останется в списке — '
                        'её можно изменить и включить снова.',
                        style: TextStyle(color: mutedText, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                error = dateError = null;
                final n = int.tryParse(every.text) ?? 0;
                if (mode != 'interval' && ScheduleTask.parseTime(time.text) == null) {
                  error = 'Формат: ЧЧ:ММ';
                }
                if (mode == 'once') {
                  final d = ScheduleTask.parseDate(date.text);
                  if (d == null) {
                    dateError = 'Формат: ДД.ММ.ГГГГ';
                  } else if (error == null &&
                      ScheduleTask(script: script, mode: 'once', time: time.text.trim(), date: d)
                          .onceAt!
                          .isBefore(DateTime.now())) {
                    error = 'Это время уже прошло';
                  }
                }
                if (mode == 'interval' && n < 1) error = 'Не меньше 1 минуты';
                if (error != null || dateError != null) {
                  setState(() {});
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(task == null ? 'Добавить' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(every.text) ?? 60;
    final t = task ?? ScheduleTask(script: script);
    final changedWhen = task == null ||
        task.mode != mode ||
        task.time != time.text.trim() ||
        task.date != (ScheduleTask.parseDate(date.text) ?? '') ||
        task.everyMin != n;
    t
      ..script = script
      ..mode = mode
      ..time = time.text.trim()
      ..date = mode == 'once' ? (ScheduleTask.parseDate(date.text) ?? '') : ''
      ..everyMin = n < 1 ? 60 : n;
    if (task == null) {
      app.addTask(t);
    } else {
      // A new time of a one-time task makes it wait again.
      if (changedWhen && mode == 'once') {
        t
          ..lastRun = null
          ..enabled = true;
      }
      app.saveSchedule();
    }
  }

  /// New rule: a script tied to a program.
  Future<void> _addRule(BuildContext context) async {
    if (app.scripts.isEmpty) return;
    var script = app.current ?? app.scripts.first;
    var trigger = 'start';
    var leave = 'stop';
    final target = TextEditingController();
    final windows = app.otherWindows();
    String? error;
    final rule = await showDialog<AutoRule>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Скрипт для программы'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Скрипт', style: TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: script,
                  items: [
                    for (final n in app.scripts)
                      DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => script = v ?? script),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: target,
                  decoration: InputDecoration(
                    labelText: 'Программа',
                    helperText: 'Имя процесса (game.exe), часть заголовка окна или «процесс|заголовок»',
                    helperMaxLines: 2,
                    errorText: error,
                    suffixIcon: windows.isEmpty
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: 'Выбрать из открытых окон',
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (v) => setState(() {
                              target.text = v;
                              error = null;
                            }),
                            itemBuilder: (_) => [
                              for (final w in windows)
                                PopupMenuItem(
                                  value: w.process,
                                  child: Text('${w.process} — ${w.title}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Когда запускать', style: TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: trigger,
                  items: const [
                    DropdownMenuItem(value: 'start', child: Text('Когда программа запускается')),
                    DropdownMenuItem(value: 'focus', child: Text('Когда её окно становится активным')),
                  ],
                  onChanged: (v) => setState(() {
                    trigger = v ?? trigger;
                    if (trigger == 'start' && leave == 'pause') leave = 'stop';
                  }),
                ),
                const SizedBox(height: 8),
                Text(trigger == 'focus' ? 'Когда окно перестаёт быть активным' : 'Когда программа закрывается',
                    style: const TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<String>(
                  isExpanded: true,
                  value: leave,
                  items: [
                    const DropdownMenuItem(value: 'stop', child: Text('Остановить скрипт')),
                    if (trigger == 'focus')
                      const DropdownMenuItem(
                          value: 'pause',
                          child: Text('Пауза, пока окно снова не станет активным')),
                    const DropdownMenuItem(value: 'none', child: Text('Ничего не делать')),
                  ],
                  onChanged: (v) => setState(() => leave = v ?? leave),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (target.text.trim().isEmpty) {
                  setState(() => error = 'Укажите программу');
                  return;
                }
                Navigator.pop(
                    ctx,
                    AutoRule(
                        script: script,
                        target: target.text.trim(),
                        trigger: trigger,
                        leave: leave));
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (rule != null) app.addAutoRule(rule);
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
        child: Text(text, style: const TextStyle(color: mutedText, fontSize: 12.5)),
      );

  Widget _addButton(String label, VoidCallback? onPressed) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add),
            label: Text(label),
          ),
        ),
      );

  Widget _timeTab(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _addButton('Добавить задачу', app.scripts.isEmpty ? null : () => _editTask(context)),
          _note('Скрипты запускаются сами, пока SmartClicker открыт (можно свернуть в трей; закрытая программа ничего не запустит). Если в нужный момент уже работает другой скрипт '
              'или идёт запись, запуск откладывается (для ежедневных и разовых задач — не дольше чем на 10 минут). '
              'Запуск по расписанию идёт без отсчёта и с теми же лимитами и клавишами остановки.'),
          Expanded(
            child: app.schedule.isEmpty
                ? const Center(
                    child: Text('Задач пока нет', style: TextStyle(color: mutedText)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final t in app.schedule)
                        ListTile(
                          leading: Switch(
                            value: t.enabled,
                            onChanged: (v) {
                              t.enabled = v;
                              app.saveSchedule();
                            },
                          ),
                          title: Text('${t.script} — ${t.describe()}'),
                          subtitle: Text(
                              (app.scripts.contains(t.script) ? '' : 'Скрипт не найден!   ·   ') +
                                  (t.lastRun == null
                                      ? 'ещё не запускался'
                                      : 'последний запуск: ${timeStamp(t.lastRun!)}'),
                              style: const TextStyle(color: mutedText)),
                          onTap: () => _editTask(context, t),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Изменить задачу',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editTask(context, t),
                              ),
                              IconButton(
                                tooltip: 'Удалить задачу',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => app.removeTask(t),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      );

  Widget _programTab(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _addButton('Добавить правило', app.scripts.isEmpty ? null : () => _addRule(context)),
          _note('Скрипт запускается сам, когда открывается нужная программа или её окно становится активным, '
              'и может остановиться или встать на паузу, когда программа закрыта или вы переключились в другое окно. '
              'Программа, уже открытая в момент запуска SmartClicker, не считается «только что запущенной». '
              'Если в этот момент работает другой скрипт, автозапуск ждёт, пока он закончится.'),
          Expanded(
            child: app.autoRules.isEmpty
                ? const Center(
                    child: Text('Правил пока нет', style: TextStyle(color: mutedText)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final r in app.autoRules)
                        ListTile(
                          leading: Switch(
                            value: r.enabled,
                            onChanged: (v) {
                              r.enabled = v;
                              app.saveAutoRules();
                            },
                          ),
                          title: Text(r.script),
                          subtitle: Text(
                              '${app.scripts.contains(r.script) ? '' : 'Скрипт не найден!   ·   '}'
                              'Запуск ${r.describe()}   ·   '
                              '${r.lastRun == null ? 'ещё не запускался' : 'последний запуск: ${timeStamp(r.lastRun!)}'}',
                              style: const TextStyle(color: mutedText)),
                          trailing: IconButton(
                            tooltip: 'Удалить правило',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => app.removeAutoRule(r),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            pageHeader('Автозапуск'),
            TabBar(
              tabs: [
                Tab(text: 'По расписанию (${app.schedule.length})'),
                Tab(text: 'По программе (${app.autoRules.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_timeTab(context), _programTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- history
